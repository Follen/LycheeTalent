"""Resume hero gaps and improve task-added records while preserving the original publication."""
import argparse
import concurrent.futures
import hashlib
import json
import re
import sqlite3
import subprocess
import time
from pathlib import Path

from client import WCL,WCLPermissionError
from collect import CLASSES, HERO_CHOICES, PATCH, ROOT, FULL_TREE_BUILD, FULL_TREE_POINTS, FULL_TREE_REFERENCE, collect_one, complete_tree, coverage, normalize, render_package


FOCUS_SPECS={('Death Knight','Blood'),('Paladin','Holy'),('Rogue','Subtlety'),('Shaman','Elemental'),('Warrior','Arms')}
BASELINE_REVISION='11bcd5a677a144316a220cac58557d7f0c58bdb1'


class BudgetExhausted(RuntimeError):
    pass


class CachedClient(WCL):
    def __init__(self, credentials, state, reserve):
        self.state=state;self.reserve=reserve;self.network=0;self.hits=0;self.prefix_hits=0;self.page_cache={};self.page_sources={};self.replay=False
        super().__init__(credentials)
        self.rate=super().query('{rateLimitData{limitPerHour pointsSpentThisHour pointsResetIn}}')['rateLimitData']
        self.state.execute('CREATE TABLE IF NOT EXISTS responses(key TEXT PRIMARY KEY,fetched INTEGER,query TEXT,payload TEXT)')
        self.state.execute('CREATE TABLE IF NOT EXISTS response_errors(key TEXT PRIMARY KEY,fetched INTEGER,query TEXT,error TEXT,payload TEXT)')
        self.state.commit()

    @property
    def remaining(self):
        return self.rate['limitPerHour']-self.rate['pointsSpentThisHour']

    def query(self, query, variables=None):
        key=hashlib.sha256(json.dumps([query,variables],sort_keys=True).encode()).hexdigest()
        page=int(re.search(r'page:(\d+)',query).group(1)) if 'characterRankings(' in query else None
        if self.replay and page in self.page_cache:
            self.hits+=1;self.prefix_hits+=1;self.page_sources[page]={'cacheReplayed':True}
            return {'worldData':{'encounter':{'characterRankings':self.page_cache[page]}}}
        row=self.state.execute('SELECT payload,fetched FROM responses WHERE key=?',(key,)).fetchone()
        if row:
            self.hits+=1
            if page is not None:self.page_sources[page]={'cacheReplayed':True,'sourceFetchedAt':row[1]}
            return json.loads(row[0])
        denied=self.state.execute('SELECT fetched,error,payload FROM response_errors WHERE key=?',(key,)).fetchone()
        if denied and time.time()-denied[0]<3600:
            self.hits+=1;raise WCLPermissionError(denied[1],json.loads(denied[2]))
        if self.remaining<=self.reserve+5:
            raise BudgetExhausted('Reserved API budget reached')
        request=query.rstrip()[:-1]+'rateLimitData{limitPerHour pointsSpentThisHour pointsResetIn}}'
        self.network+=1
        try:data=super().query(request,variables)
        except WCLPermissionError as exc:
            self.state.execute('INSERT OR REPLACE INTO response_errors VALUES(?,?,?,?,?)',(key,int(time.time()),query,str(exc),json.dumps(exc.payload,ensure_ascii=False)));self.state.commit()
            rate=(exc.payload.get('data') or {}).get('rateLimitData')
            if rate:self.rate=rate
            raise
        self.rate=data['rateLimitData']
        if page is not None:self.page_sources[page]={'cacheReplayed':False,'sourceFetchedAt':int(time.time())}
        self.state.execute('INSERT INTO responses VALUES(?,?,?,?)',(key,int(time.time()),query,json.dumps(data,ensure_ascii=False)))
        self.state.commit()
        return data

    def seed(self, run):
        self.page_cache={int(page.get('page',index+1)):page for index,page in enumerate(run['rankings'])};self.page_sources={}
        # These are actual retained responses, not reconstructed empty placeholders.
        for evidence in run.get('evidence',[]):
            report=evidence['report'];key=(report['code'],report['fightID'])
            summary=evidence.get('summary') or {}
            if 'playerDetails' in summary and key not in self._combatant_summaries:
                value=concurrent.futures.Future();value.set_result(summary)
                self._combatant_summaries[key]=value


def initialize(state):
    state.execute('CREATE TABLE IF NOT EXISTS queue(key TEXT PRIMARY KEY,next_page INTEGER,has_more INTEGER,status TEXT,last_attempted INTEGER,error TEXT)')
    state.execute('CREATE TABLE IF NOT EXISTS attempts(started INTEGER,finished INTEGER,summary TEXT)')
    state.execute('CREATE TABLE IF NOT EXISTS hero_checks(key TEXT,hero INTEGER,window TEXT,status TEXT,through_page INTEGER,PRIMARY KEY(key,hero,window))')
    state.commit()


def wanted_id(job, hero):
    cls,_,index,scene,zone,enc,difficulty=job
    kind='highest' if scene=='mythic' else 'ranked'
    return f'wcl:{zone}:{enc["id"]}:{difficulty}:{CLASSES[cls][0]}:{index}:{kind}:hero:{hero["id"]}'


def make_queue(db, state, scene, window='14-days',baseline_ids=None,improve_only=False):
    present={bid:json.loads(payload) for bid,payload in db.execute('SELECT id,payload FROM builds')}
    queue=[];exhausted=[]
    for (key,) in db.execute('SELECT key FROM runs'):
        job=json.loads(key);area='mythic' if job[3]=='mythic' else 'heroic' if job[6]==4 else 'mythic-raid'
        if scene!='all' and scene!=area:continue
        choices=[];restart=False
        for hero in HERO_CHOICES[tuple(job[:2])]:
            bid=wanted_id(job,hero)
            if bid not in present:
                if not improve_only:choices.append(hero)
                continue
            if window!='partition-lifetime' or baseline_ids is None or bid in baseline_ids:continue
            check=state.execute('SELECT status FROM hero_checks WHERE key=? AND hero=? AND window=?',(key,hero['id'],window)).fetchone()
            if check and check[0] in ('found','exhausted'):continue
            build=present[bid]
            # Migration for ranking-derived winners from before per-hero checkpoints existed.
            if build.get('sourceWindow')==window and build.get('sourceOrigin','character-rankings')=='character-rankings':
                state.execute('INSERT OR REPLACE INTO hero_checks VALUES(?,?,?,?,?)',(key,hero['id'],window,'found',build['pages']));continue
            choices.append(hero)
            if not check:restart=True
        if not choices:continue
        state_key=key if window=='14-days' else window+':'+key
        saved=state.execute('SELECT next_page,has_more FROM queue WHERE key=?',(state_key,)).fetchone()
        if saved and not restart:
            page,more=saved
        else:
            page,more=(1,True) if window=='partition-lifetime' else db.execute("SELECT json_extract(payload,'$.pages')+1,json_extract(payload,'$.hasMore') FROM runs WHERE key=?",(key,)).fetchone()
            state.execute('INSERT OR REPLACE INTO queue VALUES(?,?,?,?,?,?)',(state_key,page,more,'pending' if more else 'exhausted',0,''))
        for hero in choices:
            state.execute('INSERT OR IGNORE INTO hero_checks VALUES(?,?,?,?,?)',(key,hero['id'],window,'pending' if more else 'exhausted',page-1))
            if not more:
                state.execute('UPDATE hero_checks SET status=?,through_page=MAX(through_page,?) WHERE key=? AND hero=? AND window=? AND status<>?',
                              ('exhausted',page-1,key,hero['id'],window,'found'))
        item={'key':key,'state_key':state_key,'job':job,'choices':choices,'start':page,'area':area}
        (queue if more else exhausted).append(item)
    state.commit()
    priority={'mythic':0,'heroic':1,'mythic-raid':2}
    queue.sort(key=lambda row:(priority[row['area']],tuple(row['job'][:2]) not in FOCUS_SPECS,row['start'],row['key']))
    return queue,exhausted


def insert_new(db, builds):
    added=[]
    for build in builds:
        cursor=db.execute('INSERT OR IGNORE INTO builds VALUES(?,?,?)',(build['id'],build['class'],json.dumps(build,ensure_ascii=False)))
        if cursor.rowcount:added.append(build)
    return added


def load_baseline(state,root):
    """Pin the original published IDs independently of subsequent partial fills."""
    state.execute('CREATE TABLE IF NOT EXISTS baseline_ids(id TEXT PRIMARY KEY,revision TEXT)')
    rows=state.execute('SELECT id,revision FROM baseline_ids').fetchall()
    expected=json.loads(subprocess.check_output(['git','show',BASELINE_REVISION+':data/publication.json'],cwd=root))['builds']
    if rows:
        if len(rows)!=expected or any(rev!=BASELINE_REVISION for _,rev in rows):raise RuntimeError('Pinned baseline differs from the original publication')
        return {bid for bid,_ in rows}
    ids=set()
    for token,_ in CLASSES.values():
        source=subprocess.check_output(['git','show',BASELINE_REVISION+':addon/LycheeTalent_Data_'+token+'/Data.lua'],cwd=root).decode('utf-8')
        ids.update(re.findall(r'\["id"\]="(wcl:[^"]+)"',source))
    if len(ids)!=expected:raise RuntimeError('Original publication IDs are incomplete')
    state.executemany('INSERT INTO baseline_ids VALUES(?,?)',[(bid,BASELINE_REVISION) for bid in sorted(ids)]);state.commit()
    return ids


def upsert_candidates(db,builds,baseline_ids=None):
    db.execute('CREATE TABLE IF NOT EXISTS pending_publication(id TEXT PRIMARY KEY,class TEXT,kind TEXT)')
    db.execute('CREATE TABLE IF NOT EXISTS build_revisions(id TEXT,changed INTEGER,old_payload TEXT,new_payload TEXT)')
    db.execute('CREATE TABLE IF NOT EXISTS fill_origins(id TEXT PRIMARY KEY,window TEXT)')
    added=insert_new(db,builds);new_ids={b['id'] for b in added};improved=[]
    db.executemany('INSERT OR IGNORE INTO fill_origins VALUES(?,?)',[(b['id'],b.get('sourceWindow','14-days')) for b in added])
    for build in builds:
        if build['id'] in new_ids:continue
        if baseline_ids is None or build['id'] in baseline_ids:continue
        row=db.execute('SELECT class,payload FROM builds WHERE id=?',(build['id'],)).fetchone()
        old=json.loads(row[1])
        if row[0]!=build['class']:raise RuntimeError('Candidate class differs from its original ID')
        def priority(b):return (-b['level'],b['duration']) if b['scene']=='mythic' else (-b['score'],)
        if priority(build)>=priority(old):continue
        payload=json.dumps(build,ensure_ascii=False)
        db.execute('INSERT INTO build_revisions VALUES(?,?,?,?)',(build['id'],int(time.time()),row[1],payload))
        db.execute('UPDATE builds SET payload=? WHERE id=?',(payload,build['id']));improved.append(build)
    for kind,changes in [('added',added),('improved',improved)]:
        db.executemany('INSERT OR IGNORE INTO pending_publication VALUES(?,?,?)',[(b['id'],b['class'],kind) for b in changes])
    return added,improved


def seed_origins(db,state,baseline_ids):
    db.execute('CREATE TABLE IF NOT EXISTS fill_origins(id TEXT PRIMARY KEY,window TEXT)')
    present={bid:json.loads(payload) for bid,payload in db.execute('SELECT id,payload FROM builds') if bid not in baseline_ids}
    for payload, in state.execute('SELECT summary FROM attempts ORDER BY rowid'):
        attempt=json.loads(payload)
        db.executemany('INSERT OR IGNORE INTO fill_origins VALUES(?,?)',[(bid,attempt.get('window','14-days')) for bid in attempt.get('addedIDs',[]) if bid in present])
    db.executemany('INSERT OR IGNORE INTO fill_origins VALUES(?,?)',[(bid,b.get('sourceWindow','14-days')) for bid,b in present.items()]);db.commit()


def unpublished(db, root):
    """Recover completed upserts if an earlier process stopped before rendering its wave."""
    present={}
    for token,_ in CLASSES.values():
        path=root/'addon'/('LycheeTalent_Data_'+token)/'Data.lua'
        present[token]=set(re.findall(r'\["id"\]="([^"]+)"',path.read_text(encoding='utf-8'))) if path.exists() else set()
    pending={row[0] for row in db.execute('SELECT id FROM pending_publication')} if db.execute("SELECT 1 FROM sqlite_master WHERE name='pending_publication'").fetchone() else set()
    return [json.loads(payload) for bid,cls,payload in db.execute('SELECT id,class,payload FROM builds') if bid not in present[cls] or bid in pending]



def publish_added(db, root, classes, stamp, attempt):
    path=root/'data/publication.json';meta=json.loads(path.read_text(encoding='utf-8'))
    initial_count=meta['builds']-meta.get('partialFill',{}).get('addedBuilds',0)
    if classes:
        class_times=meta.setdefault('class_collected',{})
        for cls,(token,specs) in CLASSES.items():
            if token not in classes:continue
            builds=[json.loads(row[0]) for row in db.execute('SELECT payload FROM builds WHERE class=? ORDER BY id',(token,))]
            heroes=[[{'id':h['id'],'name':h['name']} for h in HERO_CHOICES[(cls,spec)]] for spec in specs]
            package={'version':stamp,'patch':PATCH,'heroTrees':heroes,'builds':builds}
            folder=root/'addon'/('LycheeTalent_Data_'+token);folder.mkdir(parents=True,exist_ok=True)
            (folder/'Data.lua').write_text(render_package(token,package),encoding='utf-8',newline='\n')
            class_times[token]=stamp
    scope=coverage(db);meta['coverage']=scope
    meta['builds']=db.execute('SELECT COUNT(*) FROM builds').fetchone()[0]
    meta['heroFound']=sum(row['found'] for row in scope.values())
    meta['missingHeroBuilds']=sum(row['missing'] for row in scope.values())
    partial=meta.setdefault('partialFill',{'addedBuilds':0,'runs':[]})
    partial['addedBuilds']=meta['builds']-initial_count
    partial['improvedBuilds']=db.execute('SELECT COUNT(*) FROM build_revisions').fetchone()[0] if db.execute("SELECT 1 FROM sqlite_master WHERE name='build_revisions'").fetchone() else 0
    partial['runs'].append({key:attempt[key] for key in ('started','finished','scene','jobs','rankingPages','addedBuilds','improvedBuilds','status','window')})
    if attempt['window']=='partition-lifetime':
        gap=meta.setdefault('gapFill',{'window':'partition-lifetime','addedBuilds':0,'runs':[]})
        if db.execute("SELECT 1 FROM sqlite_master WHERE name='fill_origins'").fetchone():
            gap['addedBuilds']=db.execute("SELECT COUNT(*) FROM fill_origins JOIN builds USING(id) WHERE window='partition-lifetime'").fetchone()[0]
        else:gap['addedBuilds']=db.execute("SELECT COUNT(*) FROM builds WHERE json_extract(payload,'$.sourceWindow')='partition-lifetime'").fetchone()[0]
        gap['improvedBuilds']=partial['improvedBuilds']
        gap['targetCompatibilityBuild']='12.1.5.70688'
        gap['baselineObservationDays']=meta.get('observationDays',14)
        gap['baselineRevision']=BASELINE_REVISION
        gap['completenessProfile']={'build':FULL_TREE_BUILD,'referencePublication':FULL_TREE_REFERENCE,'referenceBuilds':1795,
                                    'classSelectedPoints':{CLASSES[cls][0]:points for cls,points in FULL_TREE_POINTS.items()},
                                    'basis':'Exact per-class selected-rank totals in the fixed-build complete reference trees, not a minimum threshold',
                                    'partialRecovery':'Unique original actor CombatantInfo with Summary fallback; validate entry IDs, rank limits and legal hero selector'}
        gap['runs'].append({key:attempt[key] for key in ('started','finished','scene','jobs','rankingPages','addedBuilds','improvedBuilds','status')})
    path.write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8',newline='\n')
    return scope


def out_of_window(result, choices, cutoff):
    examples=[];selectors={h['entry']:h for h in choices};scene=result['job'][3]
    for page in result['rankings']:
        for rank in page.get('rankings') or []:
            if rank.get('startTime',0)>=cutoff:continue
            if scene=='mythic' and rank.get('medal') not in ('gold','silver','bronze'):continue
            nodes=normalize(rank)
            if not nodes:continue
            matches=[selectors[e] for e,n in nodes if n>0 and e in selectors]
            if len(matches)==1:
                examples.append({'heroTree':matches[0]['id'],'level':rank.get('hardModeLevel',0),'duration':rank.get('duration',0),'recordTime':int(rank.get('startTime',0)/1000),'report':rank['report']['code'],'fight':rank['report']['fightID']})
    examples.sort(key=lambda r:(-r['level'],r['duration']))
    return examples[:3]


class NodeCompatibility:
    def __init__(self, packet, state):
        if not packet.get('ok') or not packet['result']['complete'] or packet['result'].get('partial'):
            raise RuntimeError('Current TraitNodeEntry definitions are incomplete')
        self.build=packet['result']['sources'][0]['file']['pin']['fullBuild']
        if self.build!='12.1.5.70688':raise RuntimeError('Node definitions must be pinned to 12.1.5.70688')
        self.snapshot=packet['context']['snapshot'];self.limits=dict(packet['result']['result']['rows']);self.state=state
        state.execute('CREATE TABLE IF NOT EXISTS rejected_candidates(key TEXT PRIMARY KEY,payload TEXT)');state.commit()

    def complete(self,job):
        return lambda nodes:complete_tree(nodes,job[0])

    def accept(self, job):
        choices={h['id']:h for h in HERO_CHOICES[tuple(job[:2])]}
        def check(rank,nodes,hero):
            missing=[entry for entry,_ in nodes if entry not in self.limits]
            excess=[[entry,amount,self.limits[entry]] for entry,amount in nodes if entry in self.limits and amount>self.limits[entry]]
            selected=[choice['id'] for choice in choices.values() if [choice['entry'],1] in nodes]
            selector=hero is not None and selected==[hero['id']]
            complete=complete_tree(nodes,job[0])
            if not missing and not excess and selector and complete:return True
            value={'job':job,'rank':rank,'nodes':nodes,'missingEntries':missing,'excessRanks':excess,'legalSelector':bool(selector),'completePointBudget':complete,'actualPoints':sum(n for _,n in nodes),'expectedPoints':FULL_TREE_POINTS[job[0]],'targetBuild':self.build}
            key=hashlib.sha256(json.dumps([job,rank.get('report'),nodes],sort_keys=True).encode()).hexdigest()
            self.state.execute('INSERT OR REPLACE INTO rejected_candidates VALUES(?,?)',(key,json.dumps(value,ensure_ascii=False)));self.state.commit()
            return False
        return check


def fill(db, state, client, root, scene, pages_per_job, now,window='14-days',compatibility=None,baseline_ids=None,improve_only=False,max_page=None):
    queue,exhausted=make_queue(db,state,scene,window,baseline_ids,improve_only)
    deferred=[item for item in queue if max_page is not None and item['start']>max_page]
    queue=[item for item in queue if max_page is None or item['start']<=max_page]
    targets=sum(len(r['choices']) for r in queue)
    missing=sum(not db.execute('SELECT 1 FROM builds WHERE id=?',(wanted_id(r['job'],h),)).fetchone() for r in queue for h in r['choices'])
    print(json.dumps({'pendingJobs':len(queue),'pendingHeroes':targets,'missingHeroes':missing,'improveHeroes':targets-missing,'deferredJobs':len(deferred),
                      'exhaustedHeroes':sum(len(r['choices']) for r in exhausted),'remainingPoints':client.remaining,'reserve':client.reserve}),flush=True)
    client.replay=window=='partition-lifetime'
    cutoff=0 if window=='partition-lifetime' else (now-14*86400)*1000
    recovered=unpublished(db,root)
    pending_kinds=dict(db.execute('SELECT id,kind FROM pending_publication')) if db.execute("SELECT 1 FROM sqlite_master WHERE name='pending_publication'").fetchone() else {}
    added_classes={b['class'] for b in recovered};added_ids=[b['id'] for b in recovered if pending_kinds.get(b['id'],'added')=='added']
    improved_ids=[b['id'] for b in recovered if pending_kinds.get(b['id'])=='improved']
    visited=pages=0;status='wave_complete';blocked=[];errors=[];budget_blocked=[]
    for item in queue:
        key=item['key'];state_key=item['state_key'];retained_at,payload=db.execute('SELECT collected,payload FROM runs WHERE key=?',(key,)).fetchone();run=json.loads(payload);client.seed(run)
        end=item['start']+pages_per_job-1
        if max_page is not None:end=min(end,max_page)
        try:
            result=collect_one(client,item['job'],end,cutoff,item['choices'],start_page=item['start'],accept=compatibility.accept(item['job']) if compatibility else None,
                               complete=compatibility.complete(item['job']) if compatibility else lambda nodes:complete_tree(nodes,item['job'][0]))
        except BudgetExhausted:
            # Other jobs may already have all their necessary responses in the cache.
            status='budget_reserved';budget_blocked.append(item['job']);continue
        except Exception as exc:
            state.execute('UPDATE queue SET status=?,last_attempted=?,error=? WHERE key=?',('error',int(time.time()),str(exc),state_key));state.commit()
            errors.append({'job':item['job'],'error':str(exc)});continue
        stamp=int(time.time())
        saved_pages={int(page.get('page',index+1)):page for index,page in enumerate(run['rankings'])}
        for page in result['rankings']:saved_pages.setdefault(int(page['page']),page)
        total_scanned=sum(len(page.get('rankings') or []) for page in saved_pages.values())
        for build in result['builds']:
            build['scanned']=total_scanned
            if compatibility:
                build['targetCompatibilityBuild']=compatibility.build;build['nodeDefinitionSnapshot']=compatibility.snapshot
                build['sourceWindow']=window
                if item['job'][3]=='mythic':build['patch']='12.1'
            if hasattr(client,'page_sources'):
                for page in result['rankings']:
                    if any(row.get('report',{}).get('code')==build['report'] and row.get('report',{}).get('fightID')==build['fight'] for row in page.get('rankings') or []):
                        origin=client.page_sources.get(int(page['page']),{})
                        build.update(origin)
                        if origin.get('cacheReplayed'):build['cacheBaselineCollected']=retained_at;build['updated']=origin.get('sourceFetchedAt',retained_at)
                        break
        added,improved=upsert_candidates(db,result['builds'],baseline_ids)
        added_ids.extend(b['id'] for b in added);improved_ids.extend(b['id'] for b in improved);added_classes.update(b['class'] for b in added+improved)
        replacements={b['id']:b for b in improved}
        run['builds']=[replacements.get(b['id'],b) for b in run['builds']]+added
        run['rankings']=[saved_pages[page] for page in sorted(saved_pages)];run['evidence'].extend(result['evidence'])
        if result['pages']>=run['pages']:run['hasMore']=result['hasMore']
        run['scanned']=total_scanned;run['pages']=max(run['pages'],result['pages']);run['partialProcessed']=stamp
        db.execute('UPDATE runs SET payload=? WHERE key=?',(json.dumps(run,ensure_ascii=False),key));db.commit()
        remaining=[h for h in item['choices'] if not db.execute('SELECT 1 FROM builds WHERE id=?',(wanted_id(item['job'],h),)).fetchone()]
        found={b['heroTree'] for b in result['builds']}
        for hero in item['choices']:
            checked='found' if hero['id'] in found else 'pending' if result['hasMore'] else 'exhausted'
            state.execute('UPDATE hero_checks SET status=?,through_page=? WHERE key=? AND hero=? AND window=?',(checked,result['pages'],key,hero['id'],window))
        # Existing new IDs can still need more ranking pages before their scope is checked.
        unchecked=[h for h in item['choices'] if h['id'] not in found]
        if unchecked:remaining=unchecked
        phase='filled' if not remaining else 'pending' if result['hasMore'] else 'exhausted'
        state.execute('UPDATE queue SET next_page=?,has_more=?,status=?,last_attempted=?,error=? WHERE key=?',(result['pages']+1,int(result['hasMore']),phase,stamp,'',state_key));state.commit()
        examples=out_of_window(result,item['choices'],cutoff)
        if examples:blocked.append({'job':item['job'],'examples':examples})
        visited+=1;pages+=len(result['rankings'])
        if added or visited%10==0:print(json.dumps({'jobs':visited,'rankingPages':pages,'addedBuilds':len(added_ids),'latestAdded':[{k:b[k] for k in ('id','heroTree','heroName','level','report','fight')} for b in added],'remainingPoints':client.remaining},ensure_ascii=False),flush=True)
    finished=int(time.time())
    if errors and status=='wave_complete':status='job_errors'
    attempt={'started':now,'finished':finished,'scene':scene,'jobs':visited,'rankingPages':pages,'addedBuilds':len(added_ids),'improvedBuilds':len(improved_ids),'status':status,'window':window}
    scope=publish_added(db,root,added_classes,finished,attempt)
    if db.execute("SELECT 1 FROM sqlite_master WHERE name='pending_publication'").fetchone():db.execute('DELETE FROM pending_publication');db.commit()
    private={**attempt,'addedIDs':added_ids,'improvedIDs':improved_ids,'improveOnly':improve_only,'maxPage':max_page,'deferredJobs':len(deferred),'recoveredUnpublishedBuilds':len(recovered),'budgetBlockedJobs':budget_blocked,'outsideWindow':blocked,'errors':errors,'coverage':scope,'remainingPoints':client.remaining,'pointsResetIn':client.rate['pointsResetIn'],'networkRequests':client.network,'cacheHits':client.hits,'prefixCacheHits':getattr(client,'prefix_hits',0)}
    state.execute('INSERT INTO attempts VALUES(?,?,?)',(now,finished,json.dumps(private,ensure_ascii=False)));state.commit()
    print(json.dumps({key:value for key,value in private.items() if key not in ('outsideWindow','addedIDs','improvedIDs','budgetBlockedJobs','errors')} | {'budgetBlockedJobs':len(budget_blocked),'outsideWindowJobs':len(blocked),'outsideWindowExamples':blocked[:3],'errors':errors[:3]},ensure_ascii=False),flush=True)
    return private


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--credentials');p.add_argument('--database',type=Path,default=ROOT/'data/private/wcl.sqlite3')
    p.add_argument('--cache',type=Path,default=ROOT/'data/private/fill-missing/state.sqlite3');p.add_argument('--source-cache',type=Path)
    p.add_argument('--scene',choices=['all','mythic','heroic','mythic-raid'],default='all')
    p.add_argument('--window',choices=['14-days','partition-lifetime'],default='14-days');p.add_argument('--node-definitions',type=Path)
    p.add_argument('--pages-per-job',type=int,default=3);p.add_argument('--reserve-points',type=float,default=150);p.add_argument('--plan',action='store_true')
    p.add_argument('--improve-only',action='store_true',help='Recheck only this task\'s existing new IDs, leaving missing targets queued')
    p.add_argument('--max-page',type=int,help='Absolute page cap; defer jobs already beyond it without marking them exhausted')
    a=p.parse_args()
    if a.pages_per_job<1:p.error('--pages-per-job must be positive')
    if a.max_page is not None and a.max_page<1:p.error('--max-page must be positive')
    a.cache.parent.mkdir(parents=True,exist_ok=True)
    db=sqlite3.connect(a.database,timeout=60);state=sqlite3.connect(a.cache,timeout=60)
    for connection in (db,state):connection.execute('PRAGMA journal_mode=WAL')
    initialize(state)
    baseline=load_baseline(state,ROOT)
    seed_origins(db,state,baseline)
    if a.plan:
        queue,done=make_queue(db,state,a.scene,a.window,baseline,a.improve_only);print(json.dumps({'pendingJobs':len(queue),'pendingHeroes':sum(len(r['choices']) for r in queue),'exhaustedHeroes':sum(len(r['choices']) for r in done)}));return
    compatibility=NodeCompatibility(json.loads(a.node_definitions.read_text(encoding='utf-8-sig')),state) if a.node_definitions else None
    if a.window=='partition-lifetime' and compatibility is None:p.error('--node-definitions is required for partition-lifetime')
    client=CachedClient(a.credentials,state,a.reserve_points)
    if a.source_cache:
        with sqlite3.connect(a.source_cache) as source:
            for code,fight,payload in source.execute('SELECT code,fight,payload FROM fights'):
                value=concurrent.futures.Future();value.set_result(json.loads(payload));client._combatants[(code,fight)]=value
    fill(db,state,client,ROOT,a.scene,a.pages_per_job,int(time.time()),a.window,compatibility,baseline,a.improve_only,a.max_page)


if __name__=='__main__':main()
