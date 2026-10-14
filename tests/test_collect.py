import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/wcl'))
from collect import collect_one,normalize,lua,encode_nodes,render_package

def rank(level, report='abc', points=True, duration=100):
    return {'report':{'code':report,'fightID':1},'talents':[{'talentID':i,'points':1} for i in range(20)] if points else [],
            'hardModeLevel':level,'duration':duration,'startTime':1000,'name':str(level),'medal':'bronze','amount':100}

class FakeClient:
    def __init__(self,pages):self.pages=iter(pages)
    def query(self,_):return {'worldData':{'encounter':{'characterRankings':next(self.pages)}}}


class HolyClient:
    def __init__(self,rows):self.rows=rows;self.queries=[]
    def query(self,query):
        self.queries.append(query)
        if 'characterData' in query:
            return {'characterData':{'character':{'name':'快乐阳阳','server':{'name':'霜之哀伤'},'encounterRankings':{'ranks':self.rows}}}}
        if 'playerDetails' in query:
            return {'reportData':{'report':{'playerDetails':{'data':{'playerDetails':{'healers':[
                {'name':'Other','server':'霜之哀伤','type':'Paladin','specs':[{'spec':'Holy'}],'id':2},
                {'name':'快乐阳阳','server':'霜之哀伤','type':'Paladin','specs':[{'spec':'Holy'}],'id':9},
            ]}}}}}}
        return {'reportData':{'report':{'table':{'data':{'combatantInfo':{'talentTree':[
            {'id':i,'rank':1} for i in range(100,120)
        ]}}}}}}


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
    def test_holy_uses_yangyang_timed_log_and_exact_actor(self):
        rows=[dict(rank(24,'overtime'),bracketData=24,medal='none'),
              dict(rank(23,'slow',duration=200),bracketData=23),
              dict(rank(23,'fast',duration=100),bracketData=23),
              dict(rank(25,''),bracketData=25),
              dict(rank(25,'old'),bracketData=25,startTime=1)]
        c=HolyClient(rows)
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        result=collect_one(c,job,2,500)
        self.assertEqual(len(result['builds']),1)
        build=result['builds'][0]
        self.assertEqual((build['level'],build['report'],build['kind']),(23,'fast','highest'))
        self.assertEqual(build['nodes'],[[i,1] for i in range(100,120)])
        self.assertIn('character(id:112885599)',c.queries[0])
        self.assertIn('sourceID:9',c.queries[2])
    def test_holy_without_timed_logs_does_not_fall_back_to_another_player(self):
        c=HolyClient([dict(rank(24),bracketData=24,medal='none')])
        job=('Paladin','Holy',1,'mythic',55,{'id':12813,'name':'Murder Row'},0)
        self.assertEqual(collect_one(c,job,2,0)['builds'],[])
        self.assertEqual(len(c.queries),1)
    def test_holy_raid_keeps_general_ranking_source(self):
        c=FakeClient([{'rankings':[rank(0)],'hasMorePages':False}])
        job=('Paladin','Holy',1,'raid',53,{'id':3470,'name':'Boss'},5)
        self.assertEqual(collect_one(c,job,2,0)['builds'][0]['kind'],'ranked')
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

if __name__=='__main__':unittest.main()
