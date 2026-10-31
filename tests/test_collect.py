import sys
import unittest
import threading
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/wcl'))
from collect import collect_one,normalize,lua,encode_nodes,render_package,render_toc,CLASSES
from client import WCL

def rank(level, report='abc', points=True, duration=100):
    return {'report':{'code':report,'fightID':1},'talents':[{'talentID':i,'points':1} for i in range(20)] if points else [],
            'hardModeLevel':level,'duration':duration,'startTime':1000,'name':str(level),'medal':'bronze','amount':100}

class FakeClient:
    def __init__(self,pages):self.pages=iter(pages)
    def query(self,_):return {'worldData':{'encounter':{'characterRankings':next(self.pages)}}}


class ReportClient(WCL):
    def __init__(self,rows,*,complete=True,extra_talents=None,missing_events=False,duplicate_actor=False):
        self.rows=rows;self.queries=[];self.complete=complete;self.extra_talents=extra_talents or []
        self._combatants={};self._combatant_summaries={};self._combatants_lock=threading.Lock()
        self.missing_events=missing_events;self.duplicate_actor=duplicate_actor
    def tree(self):return ([{'id':i,'rank':1} for i in range(100,120)]+self.extra_talents) if self.complete else []
    def query(self,query):
        self.queries.append(query)
        if 'characterRankings' in query:
            return {'worldData':{'encounter':{'characterRankings':{'rankings':self.rows,'hasMorePages':False}}}}
        if 'playerDetails' in query:
            healers=[{'name':'Other','server':'Server','type':'Paladin','specs':[{'spec':'Holy'}],'id':2},
                     {'name':'Healer','server':'Server','type':'Paladin','specs':[{'spec':'Holy'}],'id':9}]
            if self.duplicate_actor:healers.append(dict(healers[1],id=10))
            return {'reportData':{'report':{
                'playerDetails':{'data':{'playerDetails':{'healers':healers}}},
                'events':{'data':[] if self.missing_events else [
                    {'sourceID':2,'talentTree':[{'id':i,'rank':1} for i in range(900,920)]},
                    {'sourceID':9,'talentTree':self.tree()}], 'nextPageTimestamp':None},
            }}}
        return {'reportData':{'report':{'table':{'data':{'playerDetails':{'healers':[{'id':2,'combatantInfo':{'talentTree':[{'id':i,'rank':1} for i in range(900,920)]}},{'id':9,'combatantInfo':{'talentTree':self.tree()}}]}}}}}}


class CollectionTests(unittest.TestCase):
    job=('Warrior','Arms',1,'mythic',55,{'id':12993,'name':'Altar of Fangs'},0)
    def test_highest_with_talents(self):
        c=FakeClient([{'rankings':[rank(25,points=False),rank(24,report=''),rank(23),rank(22)],'hasMorePages':True}])
        r=collect_one(c,self.job,2,0)
        self.assertEqual(r['builds'][0]['level'],23)
        self.assertEqual(r['builds'][0]['sample'],2)
    def test_pagination_when_no_usable_talents(self):
        c=FakeClient([{'rankings':[rank(25,points=False)],'hasMorePages':True},{'rankings':[rank(20)],'hasMorePages':False}])
        r=collect_one(c,self.job,2,0)
        self.assertEqual(r['pages'],2)
        self.assertEqual(r['builds'][0]['level'],20)
    def test_empty_is_not_fabricated(self):
        c=FakeClient([{'rankings':[rank(25,points=False)],'hasMorePages':False}])
        self.assertEqual(collect_one(c,self.job,2,0)['builds'],[])
    def test_duplicate_talent_rejected(self):
        r=rank(20);r['talents'].append(r['talents'][0]);self.assertIsNone(normalize(r))
    def test_holy_uses_the_global_highest_timed_record(self):
        rows=[rank(29,'overtime'),rank(27,'slow',duration=200),rank(27,'fast',duration=100),rank(26,'lower')]
        rows[0]['medal']='none'
        client=FakeClient([{'rankings':rows,'hasMorePages':False}])
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(client,job,2,0)
        self.assertEqual((result['builds'][0]['level'],result['builds'][0]['report']),(27,'fast'))
        self.assertEqual(result['builds'][0]['medal'],'bronze')
        self.assertEqual(result['builds'][0]['duration'],100)
    def test_overtime_is_excluded_before_level_comparison(self):
        overtime=rank(30,'overtime');overtime['medal']='none'
        c=FakeClient([{'rankings':[overtime,rank(25,'timed')],'hasMorePages':False}])
        self.assertEqual(collect_one(c,self.job,2,0)['builds'][0]['report'],'timed')
    def test_missing_rank_talents_are_recovered_from_the_exact_log_actor(self):
        first=dict(rank(27,'missing',points=False),name='Healer',server={'name':'Server'})
        c=ReportClient([first,rank(26,'lower')])
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(c,job,2,0)
        self.assertEqual(result['builds'][0]['report'],'missing')
        self.assertEqual(result['builds'][0]['nodes'],[[i,1] for i in range(100,120)])
        self.assertEqual(result['evidence'][0]['actor']['id'],9)
        self.assertEqual(result['evidence'][0]['combatantInfo']['sourceID'],9)
        self.assertEqual(len(result['evidence']),1)
        self.assertEqual(result['rankings'][0]['rankings'][0],first)
    def test_incomplete_source_log_moves_to_next_complete_rank(self):
        first=dict(rank(27,'missing',points=False),name='Healer',server={'name':'Server'})
        c=ReportClient([first,rank(26,'lower')],complete=False)
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(c,job,2,0)
        self.assertEqual(result['builds'][0]['report'],'lower')
        self.assertEqual(result['builds'][0]['level'],26)
    def test_holy_raid_keeps_general_ranking_source(self):
        c=FakeClient([{'rankings':[rank(0)],'hasMorePages':False}])
        job=('Paladin','Holy',1,'raid',53,{'id':3470,'name':'Boss'},5)
        self.assertEqual(collect_one(c,job,2,0)['builds'][0]['kind'],'ranked')
    def test_each_hero_keeps_its_highest_complete_candidate(self):
        trickster=rank(24,'trickster');trickster['talents'].append({'talentID':123370,'points':1})
        deathstalker=rank(25,'deathstalker');deathstalker['talents'].append({'talentID':123373,'points':1})
        c=FakeClient([{'rankings':[deathstalker,trickster],'hasMorePages':True}])
        job=('Rogue','Subtlety',3,'mythic',55,{'id':12993,'name':'Encounter'},0)
        heroes=[{'entry':123370,'id':51,'name':'Trickster'},{'entry':123373,'id':53,'name':'Deathstalker'}]
        builds=collect_one(c,job,2,0,heroes)['builds']
        self.assertEqual([(b['heroTree'],b['level']) for b in builds],[(51,24),(53,25)])
        self.assertTrue(builds[0]['id'].endswith(':highest:hero:51'))
        self.assertEqual(builds[1]['heroName'],'Deathstalker')
    def test_missing_hero_continues_past_a_page_with_other_hero(self):
        good=rank(24,'trickster');good['talents'].append({'talentID':123370,'points':1})
        other=rank(23,'deathstalker');other['talents'].append({'talentID':123373,'points':1})
        c=FakeClient([{'rankings':[good],'hasMorePages':True},{'rankings':[other],'hasMorePages':False}])
        job=('Rogue','Subtlety',3,'mythic',55,{'id':12993,'name':'Encounter'},0)
        heroes=[{'entry':123370,'id':51,'name':'Trickster'},{'entry':123373,'id':53,'name':'Deathstalker'}]
        result=collect_one(c,job,2,0,heroes)
        self.assertEqual(result['pages'],2)
        self.assertEqual(len(result['builds']),2)
    def test_missing_hero_is_not_fabricated_from_other_hero(self):
        good=rank(24,'trickster');good['talents'].append({'talentID':123370,'points':1})
        c=FakeClient([{'rankings':[good],'hasMorePages':False}])
        job=('Rogue','Subtlety',3,'mythic',55,{'id':12993,'name':'Encounter'},0)
        heroes=[{'entry':123370,'id':51,'name':'Trickster'},{'entry':123373,'id':53,'name':'Deathstalker'}]
        self.assertEqual([b['heroTree'] for b in collect_one(c,job,2,0,heroes)['builds']],[51])
    def test_unknown_hero_missing_talents_can_beat_the_other_hero(self):
        first=rank(26,'hero-a');first['talents'].append({'talentID':123359,'points':1})
        unknown=dict(rank(25,'unknown',points=False),name='Healer',server={'name':'Server'})
        lower=rank(24,'lower-b');lower['talents'].append({'talentID':123362,'points':1})
        client=ReportClient([first,unknown,lower],extra_talents=[{'id':123362,'rank':1}])
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        heroes=[{'entry':123359,'id':49,'name':'Lightsmith'},{'entry':123362,'id':50,'name':'Herald of the Sun'}]
        builds=collect_one(client,job,2,0,heroes)['builds']
        self.assertEqual([(b['heroTree'],b['level'],b['report']) for b in builds],[(49,26,'hero-a'),(50,25,'unknown')])
        self.assertEqual(len(client.queries),2)
    def test_unknown_hero_worse_than_both_bests_does_not_fetch_log(self):
        first=rank(26,'hero-a');first['talents'].append({'talentID':123359,'points':1})
        second=rank(25,'hero-b');second['talents'].append({'talentID':123362,'points':1})
        unknown=dict(rank(24,'unknown',points=False),name='Healer',server={'name':'Server'})
        client=ReportClient([first,second,unknown])
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        heroes=[{'entry':123359,'id':49,'name':'Lightsmith'},{'entry':123362,'id':50,'name':'Herald of the Sun'}]
        self.assertEqual(len(collect_one(client,job,2,0,heroes)['builds']),2)
        self.assertEqual(len(client.queries),1)
    def test_zero_rank_selector_does_not_hide_unknown_hero(self):
        first=rank(26,'hero-a');first['talents'].append({'talentID':123359,'points':1})
        unknown=dict(rank(25,'unknown',points=False),name='Healer',server={'name':'Server'},talents=[{'talentID':123359,'points':0}])
        lower=rank(24,'lower-b');lower['talents'].append({'talentID':123362,'points':1})
        client=ReportClient([first,unknown,lower],extra_talents=[{'id':123362,'rank':1}])
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        heroes=[{'entry':123359,'id':49,'name':'Lightsmith'},{'entry':123362,'id':50,'name':'Herald of the Sun'}]
        builds=collect_one(client,job,2,0,heroes)['builds']
        self.assertEqual(next(b['report'] for b in builds if b['heroTree']==50),'unknown')
    def test_fight_events_are_shared_across_ranking_jobs(self):
        missing=dict(rank(26,'shared',points=False),name='Healer',server={'name':'Server'})
        client=ReportClient([missing])
        one=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        two=('Paladin','Holy',1,'mythic',55,{'id':12825,'name':'Other'},0)
        a=collect_one(client,one,1,0)['builds'][0]
        client.rows=[dict(missing,name='Other')]
        b=collect_one(client,two,1,0)['builds'][0]
        self.assertEqual(a['nodes'],[[i,1] for i in range(100,120)])
        self.assertEqual(b['nodes'],[[i,1] for i in range(900,920)])
        self.assertEqual(sum('events(' in q for q in client.queries),1)
        self.assertEqual(sum('table(' in q for q in client.queries),0)
    def test_missing_event_tree_uses_summary_for_the_exact_actor(self):
        missing=dict(rank(26,'shared',points=False),name='Healer',server={'name':'Server'})
        client=ReportClient([missing],missing_events=True)
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(client,job,1,0)
        self.assertEqual(result['builds'][0]['nodes'],[[i,1] for i in range(100,120)])
        self.assertNotIn('sourceID:',client.queries[-1])
        self.assertEqual(result['evidence'][0]['summaryActor']['id'],9)
        self.assertIn('summary',result['evidence'][0])
    def test_missing_event_summary_fallback_is_shared_for_the_fight(self):
        missing=dict(rank(26,'shared',points=False),name='Healer',server={'name':'Server'})
        client=ReportClient([missing],missing_events=True)
        one=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        two=('Paladin','Holy',1,'mythic',55,{'id':12825,'name':'Other'},0)
        a=collect_one(client,one,1,0)['builds'][0]
        b=collect_one(client,two,1,0)['builds'][0]
        self.assertEqual(a['nodes'],b['nodes'])
        self.assertEqual(sum('events(' in q for q in client.queries),1)
        self.assertEqual(sum('table(' in q for q in client.queries),1)
    def test_ambiguous_actor_is_not_assigned_another_players_nodes(self):
        missing=dict(rank(26,'ambiguous',points=False),name='Healer',server={'name':'Server'})
        client=ReportClient([missing,rank(25,'complete')],duplicate_actor=True)
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(client,job,1,0)
        self.assertEqual(result['builds'][0]['report'],'complete')
        self.assertEqual(sum('table(' in q for q in client.queries),0)
    def test_combatant_events_follow_next_page_before_selecting_actor(self):
        missing=dict(rank(26,'paged',points=False),name='Healer',server={'name':'Server'})
        class Paged(ReportClient):
            def query(self,query):
                if 'startTime:50' in query:
                    self.queries.append(query)
                    return {'reportData':{'report':{'events':{'data':[{'sourceID':9,'talentTree':self.tree()}],'nextPageTimestamp':None}}}}
                value=super().query(query)
                if 'playerDetails' in query:value['reportData']['report']['events']={'data':[],'nextPageTimestamp':50}
                return value
        client=Paged([missing]);job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(client,job,1,0)
        self.assertEqual(result['builds'][0]['nodes'],[[i,1] for i in range(100,120)])
        self.assertEqual(sum('events(' in q for q in client.queries),2)
        self.assertTrue(result['evidence'][0]['paginationComplete'])
    def test_altar_holy_uses_original_unbound_freedom_entry(self):
        missing=rank(26,'no-freedom');missing['talents'].append({'talentID':123359,'points':1})
        good=rank(25,'freedom');good['talents'].extend([{'talentID':123359,'points':1},{'talentID':131438,'points':1}])
        c=FakeClient([{'rankings':[missing,good],'hasMorePages':False}])
        job=('Paladin','Holy',1,'mythic',55,{'id':12993,'name':'Altar of Fangs'},0)
        heroes=[{'entry':123359,'id':49,'name':'Lightsmith'},{'entry':123362,'id':50,'name':'Herald of the Sun'}]
        result=collect_one(c,job,2,0,heroes)
        self.assertEqual([(b['heroTree'],b['level'],b['report']) for b in result['builds']],[(49,25,'freedom')])
        self.assertIn([131438,1],result['builds'][0]['nodes'])
    def test_lua_serialization_escapes(self):
        self.assertEqual(lua('a"b\\c\n'), '"a\\"b\\\\c\\n"')
    def test_packed_publication_reuses_identical_nodes(self):
        nodes=[[101,1],[102,2]]
        package={'version':1,'patch':'12.1','builds':[
            {'id':'one','nodes':nodes,'score':100},
            {'id':'two','nodes':nodes,'score':200},
        ]}
        rendered=render_package('MAGE',package)
        self.assertEqual(encode_nodes(nodes),'101:1;102:2;')
        self.assertEqual(rendered.count('101:1;102:2;'),1)
        self.assertEqual(rendered.count('["nodes"]=n[1]'),2)
        self.assertIn('["score"]=200',rendered)


class TocGenerationTests(unittest.TestCase):
    def test_generated_metadata_follows_main_addon(self):
        text=render_toc('MAGE','## Interface: 120205\r\n## Version: 1.0.99\r\n')
        self.assertIn('## Interface: 120205\n',text)
        self.assertIn('## Version: 1.0.99\n',text)
        self.assertIn('## LoadOnDemand: 1\n## Dependencies: LycheeTalent\n',text)
        self.assertTrue(text.endswith('Data.lua\n'))

    def test_current_class_tocs_are_reproduced(self):
        root=Path(__file__).resolve().parents[1]/'addon'
        main=(root/'LycheeTalent/LycheeTalent.toc').read_text(encoding='utf-8')
        for token,_ in CLASSES.values():
            with self.subTest(token=token):
                folder=root/('LycheeTalent_Data_'+token)
                self.assertEqual(render_toc(token,main),(folder/(folder.name+'.toc')).read_text(encoding='utf-8'))

    def test_missing_or_invalid_metadata_fails_before_publication(self):
        for text in ('','## Interface: 120105','## Version: 1.0.18',
                     '## Interface: current\n## Version: 1.0.18',
                     '## Interface: 120105\n## Version: next'):
            with self.subTest(text=text),self.assertRaises(ValueError):
                render_toc('MAGE',text)

if __name__=='__main__':unittest.main()
