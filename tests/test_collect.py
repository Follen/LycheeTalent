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
