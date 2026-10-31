"""Collect logged talent builds, preserve evidence in SQLite, publish class Lua shards."""
import argparse
import concurrent.futures
import hashlib
import json
import re
import sqlite3
import time
from pathlib import Path
from client import WCL,WCLPermissionError

ROOT=Path(__file__).resolve().parents[2]
CLASSES={"Warrior":("WARRIOR",["Arms","Fury","Protection"]),"Paladin":("PALADIN",["Holy","Protection","Retribution"]),
"Hunter":("HUNTER",["Beast Mastery","Marksmanship","Survival"]),"Rogue":("ROGUE",["Assassination","Outlaw","Subtlety"]),
"Priest":("PRIEST",["Discipline","Holy","Shadow"]),"Death Knight":("DEATHKNIGHT",["Blood","Frost","Unholy"]),
"Shaman":("SHAMAN",["Elemental","Enhancement","Restoration"]),"Mage":("MAGE",["Arcane","Fire","Frost"]),
"Warlock":("WARLOCK",["Affliction","Demonology","Destruction"]),"Monk":("MONK",["Brewmaster","Mistweaver","Windwalker"]),
"Druid":("DRUID",["Balance","Feral","Guardian","Restoration"]),"Demon Hunter":("DEMONHUNTER",["Havoc","Vengeance","Devourer"]),
"Evoker":("EVOKER",["Devastation","Preservation","Augmentation"])}
ICONS={12993:7956175,12825:7266214,61762:2011123,12813:7266213,112521:4578416,61877:2011143,12859:7354408,12923:7439626,
3470:7966621,3445:7966620,3455:7966618,3497:7966622,3420:7966619,3421:7966623,3429:7966625,3492:7966624,3379:3012069,3513:8214195}
MAPS={12993:2993,12825:2825,61762:1762,12813:2813,112521:2521,61877:1877,12859:2859,12923:2923}
PATCH='12.1.5'
RAID_PARTITION=2
HERO_DATA=json.loads(Path(__file__).with_name('hero-trees.json').read_text(encoding='utf-8'))
HERO_CHOICES={(row['class'],row['spec']):row['heroes'] for row in HERO_DATA['specs']}
# Verified Unbound Freedom entry for Holy Paladin, retail 12.1.5.70688.
HOLY_FREEDOM_ENTRY=131438
# Complete selected-entry totals for fixed retail 12.1.5.70688, including granted ranks.
# All 1795 baseline trees agree per class, across every spec and represented hero pair.
FULL_TREE_BUILD='12.1.5.70688'
FULL_TREE_REFERENCE='11bcd5a677a144316a220cac58557d7f0c58bdb1'
FULL_TREE_POINTS={'Warrior':85,'Paladin':86,'Hunter':84,'Rogue':84,'Priest':85,'Death Knight':84,
                  'Shaman':84,'Mage':84,'Warlock':84,'Monk':85,'Druid':86,'Demon Hunter':84,'Evoker':85}


def complete_tree(nodes,cls):
    return bool(nodes) and sum(amount for _,amount in nodes)==FULL_TREE_POINTS[cls]

def localize(scenes):
    order=json.loads(Path(__file__).with_name('raid-order.json').read_text(encoding='utf-8'))
    journal=json.loads(Path(__file__).with_name('encounter-maps.json').read_text(encoding='utf-8'))
    for s in scenes:
        entry=order['encounters'].get(str(s['id'])) if s['scene']=='raid' else None
        if entry:
            s['raidOrder']=order['instanceOrder'].index(entry[0])+1
            s['bossOrder']=entry[1]
        if s['scene']=='raid' and str(s['id']) in journal['encounters']:
            s.update(journal['encounters'][str(s['id'])])
    source=Path(__file__).with_name('scenario-locales.json')
    if not source.exists():return scenes
    names=json.loads(source.read_text(encoding='utf-8-sig'))
    bosses=dict(names['boss']['rows']);maps=dict(names['maps']['rows'])
    for s in scenes:
        sid=int(s['id']);s['mapID']=MAPS.get(sid)
        name=maps.get(MAPS.get(sid)) if s['scene']=='mythic' else bosses.get(sid)
        if name:s['zhCN']=name
    return scenes

def coverage(db):
    expected={'mythic':0,'heroic':0,'mythicRaid':0}
    for key, in db.execute('SELECT key FROM runs'):
        job=json.loads(key);area='mythic' if job[3]=='mythic' else 'heroic' if job[6]==4 else 'mythicRaid'
        expected[area]+=len(HERO_CHOICES[tuple(job[:2])])
    found={key:0 for key in expected}
    for payload, in db.execute('SELECT payload FROM builds'):
        build=json.loads(payload)
        if build['kind']=='popular':continue
        area='mythic' if build['scene']=='mythic' else 'heroic' if build['difficulty']==4 else 'mythicRaid'
        found[area]+=1
    return {key:{'expected':expected[key],'found':found[key],'missing':expected[key]-found[key]} for key in expected}


def lua(value):
    if value is None:return "nil"
    if isinstance(value,bool):return "true" if value else "false"
    if isinstance(value,(int,float)):return str(value)
    if isinstance(value,str):
        return '"'+value.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n').replace('\r','\\r')+'"'
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    return '{'+','.join('['+lua(str(k))+']='+lua(v) for k,v in value.items())+'}'


def encode_nodes(nodes):
    """Store a sorted build's exact entry/rank pairs without per-entry Lua tables."""
    if not nodes or any(len(pair)!=2 or not all(isinstance(n,int) and n>0 for n in pair) for pair in nodes):
        raise ValueError('Invalid talent nodes in published build')
    return ''.join(f'{entry}:{rank};' for entry,rank in nodes)


def render_package(token, package):
    """Intern identical node strings within a class; preserve all build metadata."""
    encoded=[];indices={};serialized=[]
    for build in package['builds']:
        nodes=encode_nodes(build['nodes'])
        if nodes not in indices:
            indices[nodes]=len(encoded)+1
            encoded.append(nodes)
        fields=[]
        for key,value in build.items():
            fields.append('['+lua(key)+']='+(f'n[{indices[nodes]}]' if key=='nodes' else lua(value)))
        serialized.append('{'+','.join(fields)+'}')
    header='LycheeTalentData = LycheeTalentData or {}\n'
    pool='local n={'+','.join(lua(value) for value in encoded)+'}\n'
    heroes=', ["heroTrees"]='+lua(package['heroTrees']) if 'heroTrees' in package else ''
    body='LycheeTalentData['+lua(token)+'] = {["version"]='+lua(package['version'])+', ["patch"]='+lua(package['patch'])+heroes+', ["builds"]={'+','.join(serialized)+'}}\n'
    return header+pool+body

def render_toc(token, main_toc):
    """Keep regenerated class packages on the main addon's release metadata."""
    fields={}
    for line in main_toc.splitlines():
        if line.startswith('## ') and ': ' in line:
            key,value=line[3:].split(': ',1)
            fields[key]=value
    version=fields.get('Version','');interface=fields.get('Interface','')
    if not re.fullmatch(r'\d+\.\d+\.\d+',version) or not re.fullmatch(r'\d+',interface):
        raise ValueError('Main addon TOC must contain a valid Version and Interface')
    return (f'## Interface: {interface}\n'
            f'## Title: |cffd53c49Lychee|r Talent Data - {token}\n'
            '## IconTexture: Interface\\AddOns\\LycheeTalent\\Media\\talent-icon.tga\n'
            '## LoadOnDemand: 1\n## Dependencies: LycheeTalent\n'
            f'## Version: {version}\nData.lua\n')


def normalize(rank):
    report=rank.get("report") or {}
    if not report.get("code") or not report.get("fightID"):return None
    talents=rank.get("talents") or []
    if len(talents)<20:return None
    points={}
    for t in talents:
        tid=t.get("talentID"); amount=t.get("points")
        if not isinstance(tid,int) or not isinstance(amount,int) or not 1<=amount<=63:return None
        if tid in points:return None
        points[tid]=amount
    return sorted(([tid,n] for tid,n in points.items()))


def report_talents(client,rank,cls,spec,evidence,complete=None):
    """Recover the selected actor's original fight talents when rankings omit them."""
    report=rank.get('report') or {};server=rank.get('server') or {}
    if not report.get('code') or not report.get('fightID') or not rank.get('name') or not server.get('name'):
        return None
    fight=client.combatants(report['code'],report['fightID'])
    details=fight['playerDetails'];groups=details['data']['playerDetails']
    actors=[actor for group in groups.values() if isinstance(group,list) for actor in group if isinstance(actor,dict)]
    matches=[actor for actor in actors if actor.get('name')==rank['name'] and actor.get('server')==server['name']
             and actor.get('type','').replace(' ','')==cls.replace(' ','')
             and any(entry.get('spec','').replace(' ','')==spec.replace(' ','') for entry in actor.get('specs',[]))]
    if len(matches)!=1:
        evidence.append({'report':report,'details':details,'rankName':rank['name'],'rankServer':server['name'],'reason':'ranked actor not unique'})
        return None
    actor=matches[0]
    events=[event for page in fight['pages'] for event in page['data'] if event.get('sourceID')==actor['id']]
    for event in events:
        talents=event.get('talentTree') or []
        recovered=dict(rank,talents=[{'talentID':t['id'],'points':t['rank']} for t in talents])
        nodes=normalize(recovered)
        if nodes and (complete is None or complete(nodes)):
            evidence.append({'report':report,'actor':actor,'details':details,'combatantInfo':event,'paginationComplete':True})
            return recovered
    summary=client.combatant_summary(report['code'],report['fightID'])
    groups=summary.get('playerDetails') or {}
    summary_actor=next((item for group in groups.values() if isinstance(group,list) for item in group if item.get('id')==actor['id']),None)
    evidence.append({'report':report,'actor':actor,'details':details,'summary':summary,'summaryActor':summary_actor,'paginationComplete':True})
    talents=((summary_actor or {}).get('combatantInfo') or {}).get('talentTree') or []
    return dict(rank,talents=[{'talentID':t['id'],'points':t['rank']} for t in talents])


def rank_priority(rank,scene):
    if scene=='mythic':return (-rank.get('hardModeLevel',0),rank.get('duration',10**12))
    return (-rank.get('amount',0),)


def collect_one(client,job,max_pages,cutoff,hero_choices=None,start_page=1,accept=None,complete=None):
    cls,spec,index,scene,zone,enc,difficulty=job
    metric="playerscore" if scene=="mythic" else ("hps" if spec in ("Holy","Discipline","Restoration","Mistweaver","Preservation") else "dps")
    records=[]; seen=set(); scanned=0; has_more=False;page=0;evidence=[];rankings=[]
    selectors={choice['entry']:choice for choice in hero_choices or []}
    found_heroes=set();best_keys={}
    freedom=cls=='Paladin' and spec=='Holy' and scene=='mythic' and enc['id']==12993
    def selected_hero(nodes):
        choices=[selectors[entry] for entry,amount in nodes if amount>0 and entry in selectors]
        return choices[0] if len(choices)==1 else None
    for page in range(start_page,max_pages+1):
        args={"className":cls.replace(' ',''),"specName":spec.replace(' ',''),"includeCombatantInfo":True,"page":page}
        pieces=[f'{k}:{json.dumps(v).lower() if isinstance(v,bool) else json.dumps(v)}' for k,v in args.items()]
        pieces.append('metric:'+metric)
        if scene=="raid":pieces.extend(['difficulty:'+str(difficulty),'partition:'+str(RAID_PARTITION)])
        query='{worldData{encounter(id:'+str(enc['id'])+'){characterRankings('+','.join(pieces)+')}}}'
        data=client.query(query)['worldData']['encounter']['characterRankings']
        rankings.append(data)
        ranks=data.get('rankings') or []; scanned+=len(ranks); has_more=bool(data.get('hasMorePages'))
        if scene=='mythic':
            ranks=sorted(ranks,key=lambda rank:(-rank.get('hardModeLevel',0),rank.get('duration',10**12)))
        for rank in ranks:
            if rank.get('startTime',0)<cutoff:continue
            if scene=='mythic' and rank.get('medal') not in ('gold','silver','bronze'):continue
            nodes=normalize(rank)
            if nodes and complete is not None and not complete(nodes):nodes=None
            if not nodes:
                # A partial selector does not establish a complete usable hero build.
                # Treat incomplete rows as unknown until the original actor's tree is read.
                possible=[h['id'] for h in hero_choices or []] or [0]
                priority=rank_priority(rank,scene)
                # Unknown heroes can improve any branch, including a branch with no candidate yet.
                if not any(hid not in best_keys or priority<best_keys[hid] for hid in possible):continue
                try:recovered=report_talents(client,rank,cls,spec,evidence,complete=complete)
                except WCLPermissionError as exc:
                    evidence.append({'report':rank['report'],'rankName':rank.get('name'),'rankServer':(rank.get('server') or {}).get('name'),
                                     'reason':'source-permission-denied','error':str(exc)})
                    recovered=None
                if recovered:nodes=normalize(recovered)
                if nodes and complete is not None and not complete(nodes):nodes=None
            if not nodes:continue
            if freedom and not any(entry==HOLY_FREEDOM_ENTRY and amount>0 for entry,amount in nodes):continue
            hero=selected_hero(nodes) if hero_choices else None
            if hero_choices and hero is None:continue
            if accept is not None and not accept(rank,nodes,hero):continue
            if hero:found_heroes.add(hero['id'])
            report=rank['report']; key=(report['code'],report['fightID'],rank.get('name'))
            if key in seen:continue
            seen.add(key); records.append((rank,nodes))
            hid=hero['id'] if hero else 0;priority=rank_priority(rank,scene)
            if hid not in best_keys or priority<best_keys[hid]:best_keys[hid]=priority
        # WCL rankings are ordered by their selected metric; continue when constraints exclude a page.
        if (records and (not hero_choices or len(found_heroes)==len(hero_choices))) or not has_more:break
    if not records:return {'job':job,'builds':[],'scanned':scanned,'pages':page,'hasMore':has_more,'rankings':rankings,'evidence':evidence}
    if scene=="mythic":records.sort(key=lambda v:(-v[0].get('hardModeLevel',0),v[0].get('duration',10**12)))
    else:records.sort(key=lambda v:-v[0].get('amount',0))
    frequencies={}
    for rank,nodes in records:
        sig=json.dumps(nodes,separators=(',',':')); frequencies[sig]=frequencies.get(sig,0)+1
    if hero_choices:
        selected=[]
        for choice in hero_choices:
            best=next((record for record in records if selected_hero(record[1])['id']==choice['id']),None)
            if best:selected.append(('highest' if scene=='mythic' else 'ranked',best))
    else:
        best=records[0]; common=max(records,key=lambda v:frequencies[json.dumps(v[1],separators=(',',':'))])
        selected=[('highest' if scene=='mythic' else 'ranked',best)]
        if common[1]!=best[1] and frequencies[json.dumps(common[1],separators=(',',':'))]>1:selected.append(('popular',common))
    builds=[]
    for kind,(rank,nodes) in selected:
        sig=hashlib.sha256(json.dumps(nodes).encode()).hexdigest()[:16]
        bid=f'wcl:{zone}:{enc["id"]}:{difficulty}:{CLASSES[cls][0]}:{index}:{kind}'
        hero=selected_hero(nodes) if hero_choices else None
        if hero:bid+=':hero:'+str(hero['id'])
        builds.append({'id':bid,'version':sig,'source':'builtin','name':spec+' · '+enc['name'],'scene':scene,'target':enc['name'],
            'scenarioID':str(enc['id']),'zone':zone,'difficulty':difficulty,'specIndex':index,'class':CLASSES[cls][0],
            'nodes':nodes,'kind':kind,'level':rank.get('hardModeLevel',0),'metric':metric,'score':rank.get('amount',0),
            'sample':len(records),'scanned':scanned,'pages':page,'hasMore':has_more,'count':frequencies[json.dumps(nodes,separators=(',',':'))],
            'report':rank['report']['code'],'fight':rank['report']['fightID'],'updated':int(time.time()),'patch':PATCH,
            'recordTime':int(rank.get('startTime',0)/1000),'duration':rank.get('duration',0),'medal':rank.get('medal',''),'icon':ICONS.get(enc['id'],134400)})
        if hero:builds[-1].update(heroTree=hero['id'],heroName=hero['name'])
    return {'job':job,'builds':builds,'scanned':scanned,'pages':page,'hasMore':has_more,'rankings':rankings,'evidence':evidence}

def main():
    p=argparse.ArgumentParser();p.add_argument('--credentials');p.add_argument('--class-name');p.add_argument('--pages',type=int,default=3)
    p.add_argument('--workers',type=int,default=3);p.add_argument('--days',type=int,default=14);p.add_argument('--limit',type=int,default=0)
    a=p.parse_args()
    if HERO_DATA['build']!=FULL_TREE_BUILD:raise RuntimeError('Review the fixed-build complete-tree point profile before collecting another build')
    main_toc=(ROOT/'addon/LycheeTalent/LycheeTalent.toc').read_text(encoding='utf-8-sig')
    tocs={token:render_toc(token,main_toc) for token,_ in CLASSES.values()}
    client=WCL(a.credentials)
    zones=client.query('{worldData{zones{id name frozen partitions{id name} expansion{id name} encounters{id name journalID}}}}')['worldData']['zones']
    # Explicit current-season IDs; a season bump is reviewed, never guessed from max(id).
    active=[z for z in zones if z['id'] in (55,53)]
    if len(active)!=2 or any(z['frozen'] for z in active):raise RuntimeError('Configured season is not active')
    raid=next(z for z in active if z['id']==53)
    if not any(p['id']==RAID_PARTITION and p['name']==PATCH for p in raid['partitions']):
        raise RuntimeError('Configured patch partition is not available')
    db_path=ROOT/'data/private/wcl.sqlite3';db_path.parent.mkdir(parents=True,exist_ok=True)
    db=sqlite3.connect(db_path)
    db.execute('CREATE TABLE IF NOT EXISTS runs(key TEXT PRIMARY KEY, collected INTEGER, payload TEXT)')
    db.execute('CREATE TABLE IF NOT EXISTS builds(id TEXT PRIMARY KEY, class TEXT, payload TEXT)')
    publication_path=ROOT/'data/publication.json'
    previous=json.loads(publication_path.read_text(encoding='utf-8')) if publication_path.exists() else {}
    scenes=[dict(id=str(e['id']),name=e['name'],journalID=e.get('journalID',0),scene='mythic' if z['id']==55 else 'raid',zone=z['id'],icon=ICONS.get(e['id'],134400)) for z in active for e in z['encounters']]
    jobs=[]
    for cls,(token,specs) in CLASSES.items():
        if a.class_name and cls!=a.class_name:continue
        for index,spec in enumerate(specs,1):
            for z in active:
                scene='mythic' if z['id']==55 else 'raid'
                for e in z['encounters']:
                    for difficulty in ([0] if scene=='mythic' else [4,5]):jobs.append((cls,spec,index,scene,z['id'],e,difficulty))
    partial_request=bool(a.class_name) or bool(a.limit and a.limit<len(jobs))
    if a.limit:jobs=jobs[:a.limit]
    if partial_request and (not previous or db.execute('SELECT COUNT(*) FROM builds').fetchone()[0]!=previous.get('builds')):
        db.close()
        raise RuntimeError('Partial collection requires the existing complete publication database; resume a full collection first')
    job_dates={}
    for key,collected in db.execute('SELECT key,collected FROM runs'):
        job=json.loads(key);token=CLASSES[job[0]][0]
        if collected>previous.get('class_collected',{}).get(token,previous.get('collected',0)):job_dates[key]=collected
    dirty_classes={CLASSES[json.loads(key)[0]][0] for key in job_dates}
    requested_classes={CLASSES[job[0]][0] for job in jobs}
    if partial_request and dirty_classes-requested_classes:
        db.close()
        raise RuntimeError('Other classes contain unpublished collection results; resume a full collection first')
    pending=[];now=int(time.time())
    for job in jobs:
        key=json.dumps(job,sort_keys=True)
        row=db.execute('SELECT collected FROM runs WHERE key=?',(key,)).fetchone()
        if row and now-row[0]<21600:continue
        pending.append((key,job))
    print(json.dumps({'jobs':len(jobs),'pending':len(pending),'database':str(db_path)}),flush=True)
    if not pending and not dirty_classes:
        db.close()
        print(json.dumps({'completed':0,'failed':0,'publicationUnchanged':True}),flush=True)
        return
    completed=0;failed=0;fresh_classes=set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,min(a.workers,4))) as pool:
        futures={pool.submit(collect_one,client,job,a.pages,(now-a.days*86400)*1000,HERO_CHOICES[(job[0],job[1])],
                             complete=lambda nodes,cls=job[0]:complete_tree(nodes,cls)):key for key,job in pending}
        for future in concurrent.futures.as_completed(futures):
            key=futures[future]
            try:
                result=future.result()
                cls,spec,index,scene,zone,enc,difficulty=result['job']
                prefix=f'wcl:{zone}:{enc["id"]}:{difficulty}:{CLASSES[cls][0]}:{index}:'
                db.execute('DELETE FROM builds WHERE id LIKE ?',(prefix+'%',))
                db.execute('INSERT OR REPLACE INTO runs VALUES(?,?,?)',(key,now,json.dumps(result,ensure_ascii=False)))
                for b in result['builds']:db.execute('INSERT OR REPLACE INTO builds VALUES(?,?,?)',(b['id'],b['class'],json.dumps(b,ensure_ascii=False)))
                db.commit();completed+=1;fresh_classes.add(CLASSES[cls][0]);job_dates[key]=now
            except Exception as e:
                db.rollback()
                failed+=1;print(json.dumps({'failed':json.loads(key)[:3],'reason':str(e)}),flush=True)
            if (completed+failed)%20==0:print(json.dumps({'completed':completed,'failed':failed,'total':len(pending)}),flush=True)
    if failed:
        db.close()
        raise RuntimeError(f'{failed} collection jobs failed; database retained without publishing')
    finished=int(time.time())
    full_fresh=not partial_request and len(pending)==len(jobs) and completed==len(jobs)
    changed_classes=fresh_classes|dirty_classes
    class_times=dict(previous.get('class_collected',{}))
    for token in changed_classes:
        class_times[token]=finished if token in fresh_classes else max(stamp for key,stamp in job_dates.items() if CLASSES[json.loads(key)[0]][0]==token)
    # Publish deterministic class files. No credentials, player names or gear are shipped.
    for token in [v[0] for v in CLASSES.values()]:
        if token not in changed_classes:continue
        builds=[json.loads(r[0]) for r in db.execute('SELECT payload FROM builds WHERE class=? ORDER BY id',(token,))]
        folder=ROOT/'addon'/('LycheeTalent_Data_'+token);folder.mkdir(parents=True,exist_ok=True)
        cls,specs=next((cls,specs) for cls,(class_token,specs) in CLASSES.items() if class_token==token)
        heroes=[[{'id':hero['id'],'name':hero['name']} for hero in HERO_CHOICES[(cls,spec)]] for spec in specs]
        package={'version':class_times[token],'patch':PATCH,'heroTrees':heroes,'builds':builds}
        (folder/'Data.lua').write_text(render_package(token,package),encoding='utf-8',newline='\n')
        (folder/(folder.name+'.toc')).write_text(tocs[token],encoding='utf-8',newline='\n')
    (ROOT/'addon/LycheeTalent/Scenarios.lua').write_text('local _, A = ...\nA.Scenarios = '+lua(localize(scenes))+'\n',encoding='utf-8',newline='\n')
    summary={} if full_fresh else dict(previous)
    history=list(previous.get('auditHistory',[]))
    audits={key:previous[key] for key in ('sourceRecovery','gapFill','partialFill') if key in previous}
    if audits:history.append({'collected':previous.get('collected'),'builds':previous.get('builds'),'supersededAt':finished,**audits})
    for key in audits:summary.pop(key,None)
    if history:summary['auditHistory']=history
    if full_fresh:summary.update(completed=completed,failed=0,collected=finished,observationDays=a.days,collectionStarted=now,collectionFinished=finished)
    elif not previous:summary['collected']=min(job_dates.values())
    if not full_fresh:
        partial=dict(previous.get('partialCollection',{}));dates=dict(partial.get('jobs',{}))
        for key,stamp in job_dates.items():
            job=json.loads(key);dates[f'{CLASSES[job[0]][0]}:{job[2]}:{job[4]}:{job[5]["id"]}:{job[6]}']=stamp
        partial.update(processedAt=finished,observationDays=a.days,jobs=dates,lastRun={'completed':completed,'cachedJobs':len(jobs)-len(pending),'classes':sorted(changed_classes)})
        summary['partialCollection']=partial
    scope=coverage(db)
    summary.update(builds=db.execute('SELECT COUNT(*) FROM builds').fetchone()[0],zones=[55,53],patch=PATCH,partitions={'55':1,'53':RAID_PARTITION},class_collected=class_times,
                   coverage=scope,heroExpected=sum(r['expected'] for r in scope.values()),heroFound=sum(r['found'] for r in scope.values()),missingHeroBuilds=sum(r['missing'] for r in scope.values()),
                   heroMapping={'build':HERO_DATA['build'],'snapshot':HERO_DATA['snapshot'],'capture':HERO_DATA['capture']})
    publication_path.write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8',newline='\n')
    db.close()
    print(json.dumps(summary),flush=True)
if __name__=='__main__':main()
