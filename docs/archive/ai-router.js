export const providers=['Gemini','Claude','Grok'];
export const DEMO_LIMIT=3;
export function routeAI(previous,now=new Date()){
 const day=now.toISOString().slice(0,10);
 const state=previous?.day===day?{day,usage:{...previous.usage}}:{day,usage:{}};
 const model=providers.find(p=>(Number(state.usage[p])||0)<DEMO_LIMIT);
 return {model,state,remaining:model?DEMO_LIMIT-(Number(state.usage[model])||0):0};
}
export function consumeAI(previous){const result=routeAI(previous);if(result.model)result.state.usage[result.model]=(Number(result.state.usage[result.model])||0)+1;return result;}
