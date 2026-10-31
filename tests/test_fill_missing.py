import contextlib
import io
import json
import re
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/wcl'))
from collect import HERO_CHOICES,collect_one,render_package
from fill_missing import BudgetExhausted,CachedClient,NodeCompatibility,fill,initialize,insert_new,make_queue,upsert_candidates,wanted_id
from client import WCLPermissionError


class Client:
    remaining=1000;reserve=150;network=0;hits=0
    rate={'limitPerHour':3600,'pointsSpentThisHour':2600,'pointsResetIn':100}
    def __init__(self,data=None,budget=False):self.data=data;self.budget=budget;self.queries=[]
    def seed(self,_):pass
    def query(self,query):
        self.queries.append(query)
        if self.budget:raise BudgetExhausted()
        return {'worldData':{'encounter':{'characterRankings':dict(self.data,page=int(re.search(r'page:(\d+)',query).group(1)))}}}


class FillMissingTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        (self.root/'data').mkdir();(self.root/'data/publication.json').write_text(json.dumps({'collected':100,'patch':'12.1.5','builds':1}),encoding='utf-8')
        self.db=sqlite3.connect(':memory:');self.db.execute('CREATE TABLE builds(id TEXT PRIMARY KEY,class TEXT,payload TEXT)');self.db.execute('CREATE TABLE runs(key TEXT PRIMARY KEY,collected INTEGER,payload TEXT)')
        self.state=sqlite3.connect(':memory:');initialize(self.state)
        self.job=['Warrior','Arms',1,'mythic',55,{'id':12993,'name':'Altar of Fangs'},0];self.key=json.dumps(self.job,sort_keys=True)
        self.old={'id':wanted_id(self.job,HERO_CHOICES[('Warrior','Arms')][0]),'class':'WARRIOR','nodes':[[100,1]],'version':'unchanged','heroTree':60,'kind':'highest','scene':'mythic','difficulty':0}
        self.db.execute('INSERT INTO builds VALUES(?,?,?)',(self.old['id'],'WARRIOR',json.dumps(self.old)))
        folder=self.root/'addon/LycheeTalent_Data_WARRIOR';folder.mkdir(parents=True)
        (folder/'Data.lua').write_text(render_package('WARRIOR',{'version':100,'patch':'12.1.5','builds':[self.old]}),encoding='utf-8')
        self.run={'job':self.job,'builds':[self.old],'pages':10,'hasMore':True,'scanned':1000,'rankings':[],'evidence':[]}
        self.db.execute('INSERT INTO runs VALUES(?,?,?)',(self.key,100,json.dumps(self.run)));self.db.commit()
        folder=self.root/'addon/LycheeTalent_Data_MAGE';folder.mkdir(parents=True);(folder/'Data.lua').write_bytes(b'unchanged other class\n')
    def rank(self):
        return {'report':{'code':'new-public-log','fightID':7},'talents':[{'talentID':i,'points':1} for i in range(1000,1084)]+[{'talentID':123393,'points':1}], 'hardModeLevel':22,'duration':100,'startTime':1000000,'name':'Warrior','medal':'bronze','amount':100}
    def test_continuation_starts_after_the_retained_last_page(self):
        queue,done=make_queue(self.db,self.state,'mythic')
        self.assertEqual((len(queue),len(done),queue[0]['start']),(1,0,11))
        client=Client({'rankings':[self.rank()],'hasMorePages':True})
        result=collect_one(client,self.job,11,0,queue[0]['choices'],start_page=11)
        self.assertIn('page:11',client.queries[0]);self.assertEqual(result['builds'][0]['heroTree'],62)
    def test_legacy_exhausted_queue_cannot_be_reported_as_pending_after_scope_migration(self):
        make_queue(self.db,self.state,'mythic','partition-lifetime',{self.old['id']})
        self.state.execute('UPDATE queue SET next_page=3,has_more=0,status=?',('exhausted',));self.state.commit()
        queue,done=make_queue(self.db,self.state,'mythic','partition-lifetime',{self.old['id']})
        self.assertEqual((len(queue),len(done)),(0,1))
        self.assertEqual(self.state.execute('SELECT status,through_page FROM hero_checks').fetchone(),('exhausted',2))
    def test_insert_never_replaces_a_published_recommendation(self):
        replacement=dict(self.old,version='bad-replacement')
        self.assertEqual(insert_new(self.db,[replacement]),[])
        self.assertEqual(json.loads(self.db.execute('SELECT payload FROM builds').fetchone()[0]),self.old)
    def test_baseline_cannot_be_replaced_even_by_a_higher_candidate(self):
        replacement=dict(self.old,level=30,duration=10,version='replacement')
        self.assertEqual(upsert_candidates(self.db,[replacement],{self.old['id']}),([],[]))
        self.assertEqual(json.loads(self.db.execute('SELECT payload FROM builds').fetchone()[0]),self.old)
    def test_only_new_ids_can_improve_and_never_downgrade(self):
        initial=dict(self.old,id='new-hero-id',level=22,duration=100,score=1)
        self.assertEqual(len(upsert_candidates(self.db,[initial],{self.old['id']})[0]),1)
        better=dict(initial,level=23,duration=120,report='higher-original-log')
        self.assertEqual(upsert_candidates(self.db,[better],{self.old['id']}),([],[better]))
        fastest=dict(better,duration=110,report='faster-original-log')
        self.assertEqual(upsert_candidates(self.db,[fastest],{self.old['id']}),([],[fastest]))
        for lower in (initial,dict(fastest,duration=111),dict(fastest)):
            self.assertEqual(upsert_candidates(self.db,[lower],{self.old['id']}),([],[]))
        self.assertEqual(json.loads(self.db.execute('SELECT payload FROM builds WHERE id=?',('new-hero-id',)).fetchone()[0]),fastest)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM build_revisions').fetchone()[0],2)
    def test_new_raid_recommendation_only_improves_its_corresponding_metric(self):
        initial=dict(self.old,id='new-raid-id',scene='raid',score=100)
        upsert_candidates(self.db,[initial],{self.old['id']})
        better=dict(initial,score=101)
        self.assertEqual(upsert_candidates(self.db,[better],{self.old['id']}),([],[better]))
        self.assertEqual(upsert_candidates(self.db,[dict(initial,score=99)],{self.old['id']}),([],[]))
    def test_partial_fill_preserves_full_timestamp_existing_build_and_other_class(self):
        client=Client({'rankings':[self.rank()],'hasMorePages':True})
        with contextlib.redirect_stdout(io.StringIO()),patch('fill_missing.time.time',return_value=200):
            result=fill(self.db,self.state,client,self.root,'mythic',3,200)
        self.assertEqual(result['addedBuilds'],1)
        self.assertEqual(json.loads(self.db.execute('SELECT payload FROM builds WHERE id=?',(self.old['id'],)).fetchone()[0]),self.old)
        meta=json.loads((self.root/'data/publication.json').read_text())
        self.assertEqual(meta['collected'],100);self.assertEqual(meta['class_collected'],{'WARRIOR':200})
        self.assertEqual((self.root/'addon/LycheeTalent_Data_MAGE/Data.lua').read_bytes(),b'unchanged other class\n')
        self.assertEqual(self.db.execute('SELECT collected FROM runs').fetchone()[0],100)
        queue,_=make_queue(self.db,self.state,'mythic');self.assertEqual(queue,[])
    def test_budget_stop_keeps_pending_page_and_does_not_mark_class_recollected(self):
        client=Client(budget=True)
        with contextlib.redirect_stdout(io.StringIO()):result=fill(self.db,self.state,client,self.root,'mythic',3,200)
        self.assertEqual(result['status'],'budget_reserved');self.assertEqual(result['addedBuilds'],0)
        self.assertNotIn('class_collected',json.loads((self.root/'data/publication.json').read_text()))
        self.assertEqual(make_queue(self.db,self.state,'mythic')[0][0]['start'],11)
    def test_resume_publishes_upserts_completed_before_an_interruption(self):
        client=Client({'rankings':[self.rank()],'hasMorePages':False})
        new=collect_one(client,self.job,11,0,[HERO_CHOICES[('Warrior','Arms')][1]],start_page=11)['builds'][0]
        insert_new(self.db,[new]);self.db.commit()
        with contextlib.redirect_stdout(io.StringIO()):result=fill(self.db,self.state,Client(budget=True),self.root,'mythic',3,200)
        self.assertEqual(result['addedBuilds'],1);self.assertEqual(result['recoveredUnpublishedBuilds'],1)
        self.assertIn(new['id'],(self.root/'addon/LycheeTalent_Data_WARRIOR/Data.lua').read_text())
        self.assertEqual(json.loads((self.root/'data/publication.json').read_text())['collected'],100)
    def compatibility(self, extra=None):
        rows=[[i,1] for i in range(1000,1084)]+[[123393,1]]
        if extra:rows+=extra
        packet={'ok':True,'context':{'snapshot':'fixed-test-pin'},'result':{'complete':True,'partial':False,'sources':[{'file':{'pin':{'fullBuild':'12.1.5.70688'}}}],'result':{'rows':rows}}}
        return NodeCompatibility(packet,self.state)
    def test_static_rejection_does_not_hide_a_lower_valid_original_tree(self):
        invalid=self.rank();invalid['hardModeLevel']=25;invalid['report']={'code':'invalid','fightID':1};invalid['talents'].append({'talentID':999999,'points':1})
        valid=self.rank();check=self.compatibility()
        client=Client({'rankings':[invalid,valid],'hasMorePages':False})
        heroes=[HERO_CHOICES[('Warrior','Arms')][1]]
        result=collect_one(client,self.job,11,0,heroes,start_page=11,accept=check.accept(self.job))
        self.assertEqual(result['builds'][0]['report'],'new-public-log')
        rejected=json.loads(self.state.execute('SELECT payload FROM rejected_candidates').fetchone()[0])
        self.assertEqual(rejected['missingEntries'],[999999])
    def test_static_rank_cap_is_checked_without_changing_original_nodes(self):
        check=self.compatibility();rank=self.rank();nodes=[[1000,2],[123393,1]]
        self.assertFalse(check.accept(self.job)(rank,nodes,HERO_CHOICES[('Warrior','Arms')][1]))
        self.assertEqual(nodes,[[1000,2],[123393,1]])
    def test_static_compatibility_rejects_two_selected_hero_branches(self):
        check=self.compatibility([[123390,1]])
        nodes=[[1000,1],[123390,1],[123393,1]]
        self.assertFalse(check.accept(self.job)(self.rank(),nodes,HERO_CHOICES[('Warrior','Arms')][1]))
    def test_hero_selector_does_not_make_a_31_point_subset_complete(self):
        check=self.compatibility();nodes=[[i,1] for i in range(1000,1030)]+[[123393,1]]
        self.assertFalse(check.complete(self.job)(nodes))
        self.assertFalse(check.accept(self.job)(self.rank(),nodes,HERO_CHOICES[('Warrior','Arms')][1]))
        rejected=json.loads(self.state.execute('SELECT payload FROM rejected_candidates').fetchone()[0])
        self.assertEqual((rejected['actualPoints'],rejected['expectedPoints']),(31,85))
    def test_partition_window_replays_prefix_even_when_old_tail_was_exhausted(self):
        self.run['hasMore']=False;self.db.execute('UPDATE runs SET payload=?',(json.dumps(self.run),));self.db.commit()
        self.assertEqual(make_queue(self.db,self.state,'mythic','partition-lifetime')[0][0]['start'],1)
        old=self.rank();old['startTime']=1
        client=Client({'rankings':[old],'hasMorePages':False})
        with contextlib.redirect_stdout(io.StringIO()),patch('fill_missing.time.time',return_value=200):
            result=fill(self.db,self.state,client,self.root,'mythic',3,200,'partition-lifetime',self.compatibility())
        self.assertEqual(result['addedBuilds'],1)
        b=json.loads(self.db.execute('SELECT payload FROM builds WHERE id=?',(wanted_id(self.job,HERO_CHOICES[('Warrior','Arms')][1]),)).fetchone()[0])
        self.assertEqual(b['patch'],'12.1');self.assertEqual(b['targetCompatibilityBuild'],'12.1.5.70688')
        self.assertEqual(json.loads((self.root/'data/publication.json').read_text())['gapFill']['window'],'partition-lifetime')
    def cross_wave_improvement(self,new_level,new_duration):
        baseline={self.old['id']};low=self.rank();low['hardModeLevel']=22;low['duration']=100
        with contextlib.redirect_stdout(io.StringIO()):
            first=fill(self.db,self.state,Client({'rankings':[low],'hasMorePages':True}),self.root,'mythic',3,200,'14-days',self.compatibility(),baseline)
        self.assertEqual(first['addedBuilds'],1)
        queue,_=make_queue(self.db,self.state,'mythic','partition-lifetime',baseline)
        self.assertEqual((len(queue),queue[0]['start']),(1,1))
        higher=dict(low,hardModeLevel=new_level,duration=new_duration,report={'code':'higher-lifetime-original','fightID':9})
        client=Client({'rankings':[higher],'hasMorePages':True})
        with contextlib.redirect_stdout(io.StringIO()):
            second=fill(self.db,self.state,client,self.root,'mythic',3,300,'partition-lifetime',self.compatibility(),baseline)
        self.assertEqual((second['addedBuilds'],second['improvedBuilds']),(0,1))
        bid=wanted_id(self.job,HERO_CHOICES[('Warrior','Arms')][1]);stored=json.loads(self.db.execute('SELECT payload FROM builds WHERE id=?',(bid,)).fetchone()[0])
        self.assertEqual((stored['level'],stored['duration'],stored['report']),(new_level,new_duration,'higher-lifetime-original'))
        self.assertEqual(json.loads(self.db.execute('SELECT payload FROM builds WHERE id=?',(self.old['id'],)).fetchone()[0]),self.old)
        self.assertEqual(make_queue(self.db,self.state,'mythic','partition-lifetime',baseline)[0],[])
        meta=json.loads((self.root/'data/publication.json').read_text());self.assertEqual(meta['partialFill']['addedBuilds'],1);self.assertEqual(meta['partialFill']['improvedBuilds'],1)
    def test_first_14_day_fill_is_rechecked_from_highest_page_for_lifetime_upgrade(self):
        self.cross_wave_improvement(23,110)
    def test_lifetime_recheck_can_improve_same_level_duration_without_repeating_a_finished_key(self):
        self.cross_wave_improvement(22,90)
    def test_cached_response_is_reusable_after_budget_is_reserved(self):
        rate={'limitPerHour':3600,'pointsSpentThisHour':1,'pointsResetIn':100}
        data={'answer':1,'rateLimitData':dict(rate,pointsSpentThisHour=2)}
        with patch('fill_missing.WCL.__init__',return_value=None),patch('fill_missing.WCL.query',side_effect=[{'rateLimitData':rate},data]) as query:
            client=CachedClient(None,self.state,150)
            self.assertEqual(client.query('{answer}'),data)
            client.rate=dict(client.rate,pointsSpentThisHour=3599)
            self.assertEqual(client.query('{answer}'),data)
            with self.assertRaises(BudgetExhausted):client.query('{other}')
            self.assertEqual(query.call_count,2);self.assertEqual(client.hits,1)
    def test_report_permission_error_retains_original_response_and_uses_negative_cache(self):
        rate={'limitPerHour':3600,'pointsSpentThisHour':1,'pointsResetIn':100}
        payload={'errors':[{'message':'You do not have permission to view this report.'}],'data':{'rateLimitData':dict(rate,pointsSpentThisHour=2)}}
        denied=WCLPermissionError(payload['errors'][0]['message'],payload)
        with patch('fill_missing.WCL.__init__',return_value=None),patch('fill_missing.WCL.query',side_effect=[{'rateLimitData':rate},denied]) as query:
            client=CachedClient(None,self.state,150)
            for _ in range(2):
                with self.assertRaises(WCLPermissionError):client.query('{privateReport}')
            self.assertEqual(query.call_count,2);self.assertEqual(client.network,1);self.assertEqual(client.hits,1)
            self.assertEqual(json.loads(self.state.execute('SELECT payload FROM response_errors').fetchone()[0]),payload)


if __name__=='__main__':unittest.main()
