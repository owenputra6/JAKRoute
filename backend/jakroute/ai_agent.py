import json
from .errors import RouteError
from .schemas import Preferences,merge_preferences
from .prompts import INTENT_PROMPT,TOOL_PROMPT,EXPLANATION_PROMPT

def obj(properties):
    return dict(type='object',properties=properties,required=list(properties),additionalProperties=False)

PREF_SCHEMA=obj({
 'avoid_stairs':{'type':'boolean'},'step_free':{'type':'boolean'},
 'preferred_access':{'type':'string','enum':['any','elevator','escalator','stairs']},
 'time_priority':{'type':['number','null']},'walking_priority':{'type':['number','null']},'crowd_priority':{'type':['number','null']},
 'max_walk_m':{'type':['number','null']},'required_facilities':{'type':'array','items':{'type':'string'}}})
INTENT_SCHEMA=obj({'origin_id':{'type':['string','null']},'destination_id':{'type':['string','null']},
 'via_indoor_ids':{'type':'array','items':{'type':'string'}},'focus_mode':{'type':'string','enum':['best_fit','fastest','min_walk']},
 'preferences':PREF_SCHEMA,'clarification':{'type':['string','null']}})

TOOLS=[]
for name,description in [
 ('route_outdoor','Hitung segmen luar menggunakan konektor MAPID. mode harus outdoor.'),
 ('route_indoor_plain','Hitung rute indoor minimum berjalan, tetap mematuhi obstacle dan semua constraint keras. mode min_walk.'),
 ('route_indoor_personalized','Hitung rute indoor tercepat atau paling sesuai. mode fastest atau best_fit.')]:
    modes=['outdoor'] if name=='route_outdoor' else ['min_walk'] if name=='route_indoor_plain' else ['fastest','best_fit']
    TOOLS.append(dict(type='function',name=name,description=description,strict=True,parameters=obj({
      'origin_id':{'type':'string'},'destination_id':{'type':'string'},'mode':{'type':'string','enum':modes}})))

def job_key(name,args): return (name,args['origin_id'],args['destination_id'],args['mode'])

class RouteAgent:
    def __init__(self,settings,client=None):
        self.settings=settings
        self.client=client
    def _client(self):
        if self.client is None:
            if not self.settings.openai_api_key or not self.settings.openai_model:
                raise RouteError('openai_not_configured','Isi OPENAI_API_KEY dan OPENAI_MODEL pada backend/.env.',503)
            from openai import OpenAI
            self.client=OpenAI(api_key=self.settings.openai_api_key,timeout=45,max_retries=1)
        return self.client

    def _create(self,**kwargs):
        try:
            return self._client().responses.create(model=self.settings.openai_model,store=False,
                include=['reasoning.encrypted_content'],**kwargs)
        except RouteError: raise
        except Exception as exc:
            raise RouteError('openai_error','OpenAI gagal/timeout. Periksa model, key, dan kuota pada server.',502) from exc

    def _json(self,prompt,value,schema,name):
        r=self._create(input=[{'role':'system','content':prompt},{'role':'user','content':json.dumps(value,ensure_ascii=False)}],
          text={'format':{'type':'json_schema','name':name,'schema':schema,'strict':True}})
        try: return json.loads(r.output_text)
        except (ValueError,AttributeError) as exc: raise RouteError('ai_format','AI tidak menghasilkan JSON valid.',502) from exc

    def parse_user_request(self,request,context):
        if self.settings.agent_mode=='openai':
            parsed=self._json(INTENT_PROMPT,{'request':request,'context':context},INTENT_SCHEMA,'route_intent')
        else:
            # Explicit demo parser. It does not claim to measure language-model ability.
            text=request.get('message','').lower()
            pref={**Preferences().as_dict(),**(request.get('conversation_preferences') or {})}
            pref['avoid_stairs']=any(x in text for x in ('jangan lewat tangga','hindari tangga','tanpa tangga'))
            pref['step_free']=any(x in text for x in ('kursi roda','bebas anak tangga','step free'))
            for token,kind in [('pakai lift','elevator'),('lewat lift','elevator'),('pakai eskalator','escalator')]:
                if token in text: pref['preferred_access']=kind
            focus='fastest' if any(x in text for x in ('tercepat','secepat','paling cepat')) else 'min_walk' if any(x in text for x in ('minim jalan','sesedikit','terpendek')) else 'best_fit'
            dest=request.get('destination_id')
            if not dest:
                aliases={'peron 1':'platform_1','peron 2':'platform_2','toilet':'toilet_01','mushola':'mushola_01'}
                found=[id for label,id in aliases.items() if label in text]
                if len(found)==1: dest=found[0]
                elif 'peron' in text: dest=request.get('default_platform_id')
            parsed=dict(origin_id=request.get('origin_id'),destination_id=dest,
             via_indoor_ids=request.get('via_indoor_ids',[]),focus_mode=focus,preferences=pref,
             clarification=None if dest and request.get('origin_id') else 'Pilih lokasi awal dan peron/fasilitas tujuan yang dimaksud.')
        # A conversation turn may refer to "tujuan yang sama" instead of
        # repeating an ID. Previous intent is state supplied by the client,
        # not a hardcoded destination in the notebook.
        previous_intent=request.get('conversation_context',{}).get('intent',{}) or {}
        for key in ('origin_id','destination_id'):
            if not request.get(key) and not parsed.get(key) and previous_intent.get(key):
                parsed[key]=previous_intent[key]
        if not request.get('via_indoor_ids') and not parsed.get('via_indoor_ids') and previous_intent.get('via_indoor_ids'):
            parsed['via_indoor_ids']=list(previous_intent['via_indoor_ids'])
        if not request.get('focus_mode') and previous_intent.get('focus_mode') in ('best_fit','fastest','min_walk'):
            if parsed.get('focus_mode') in (None,'best_fit'):
                parsed['focus_mode']=previous_intent['focus_mode']
        # Explicit selection remains authoritative even if model emits a different ID.
        for key in ('origin_id','destination_id'):
            if request.get(key): parsed[key]=request[key]
        if request.get('focus_mode'): parsed['focus_mode']=request['focus_mode']
        if parsed.get('focus_mode') not in ('best_fit','fastest','min_walk'): raise RouteError('ai_format','Mode AI tidak valid.',502)
        # Flutter can send the accumulated preference state between turns.
        # The current turn wins; no preference is required on the first turn.
        prior_preferences=request.get('conversation_preferences',{}) or {}
        current_preferences=request.get('preferences',{}) or {}
        explicit_preferences={**prior_preferences,**current_preferences}
        prefs=merge_preferences(explicit_preferences,parsed.get('preferences',{}))
        parsed['preferences']=prefs.as_dict()
        parsed['via_indoor_ids']=list(dict.fromkeys(request.get('via_indoor_ids',[])+parsed.get('via_indoor_ids',[])))
        known={x['id'] for x in context['places']}
        for id in [parsed.get('origin_id'),parsed.get('destination_id')]+parsed['via_indoor_ids']:
            if id and id not in known: raise RouteError('unknown_place','AI/input merujuk ID tempat yang tidak ada.',422)
        if parsed.get('origin_id') and parsed.get('destination_id'): parsed['clarification']=None
        return parsed

    def execute_jobs(self,jobs,execute,context):
        expected={job_key(j['name'],j['arguments']):j for j in jobs}
        result={}; trace=[]
        if self.settings.agent_mode=='demo':
            for key,j in expected.items():
                result[key]=execute(j['name'],j['arguments'])
                trace.append({'name':j['name'],'arguments':j['arguments'],'source':'deterministic_demo','status':result[key].get('status','ok')})
            return result,trace
        conversation=[{'role':'system','content':TOOL_PROMPT},
          {'role':'user','content':json.dumps({'jobs':jobs,'context':context},ensure_ascii=False)}]
        for turn in range(5):
            response=self._create(input=conversation,tools=TOOLS,tool_choice='required',parallel_tool_calls=True)
            # Keep ALL output items, including reasoning items required by Responses.
            conversation.extend(response.output)
            calls=[item for item in response.output if item.type=='function_call']
            if len(calls)>40: raise RouteError('ai_tool_limit','Terlalu banyak panggilan fungsi.',502)
            for call in calls:
                try:
                    args=json.loads(call.arguments)
                    if set(args)!= {'origin_id','destination_id','mode'}: raise ValueError()
                    key=job_key(call.name,args)
                    if key not in expected: raise ValueError()
                except (ValueError,KeyError,TypeError):
                    raise RouteError('ai_tool_rejected','AI meminta fungsi/parameter di luar rencana tervalidasi.',502)
                if key not in result: result[key]=execute(call.name,args)
                output={k:v for k,v in result[key].items() if k not in ('steps','geometry')}
                conversation.append({'type':'function_call_output','call_id':call.call_id,'output':json.dumps(output,ensure_ascii=False)})
                trace.append({'name':call.name,'arguments':args,'source':'openai_function_call','status':output.get('status','ok')})
            if len(result)==len(expected):
                # Deliver the tool outputs back to the same Responses conversation.
                self._create(input=conversation,tools=TOOLS,tool_choice='none',max_output_tokens=256)
                return result,trace
            conversation.append({'role':'user','content':'Lanjutkan jobs yang belum dikerjakan: '+json.dumps([v for k,v in expected.items() if k not in result])})
        raise RouteError('ai_tool_incomplete','AI tidak menyelesaikan seluruh fungsi yang wajib dipanggil.',502)

    def explain(self,selected):
        reasons=selected['reasons']
        keys=list(reasons)
        if self.settings.agent_mode=='openai':
            schema=obj({'route_id':{'type':'string'},'reason_codes':{'type':'array','items':{'type':'string'}}})
            result=self._json(EXPLANATION_PROMPT,{'selected_route_id':selected['route_id'],
                'available_reasons':reasons,'walking_m':selected['walking_m'],'duration_s':selected['duration_s'],'warnings':selected['warnings']},schema,'route_explanation')
            keys=result.get('reason_codes',[])
            if result.get('route_id')!=selected['route_id'] or not keys or any(k not in reasons for k in keys):
                raise RouteError('ai_explanation_invalid','Alasan yang dipilih AI tidak didukung hasil routing.',502)
        return ' '.join(reasons[k] for k in dict.fromkeys(keys))
