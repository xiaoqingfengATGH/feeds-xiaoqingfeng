/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require baseclass';
return baseclass.extend({
 create:function(call,changed){
  var jobs=[],running=0,flight={},waiters=[];
  function notify(id,value){changed(id,value);}
  function pump(){
   while(running<2 && jobs.length){
    (function(id){running++;notify(id,{pending:true,summary:'探测中…'});
     Promise.resolve().then(function(){return call(id);}).then(function(result){notify(id,result);},function(e){notify(id,{ok:false,summary:e.message || String(e)});}).finally(function(){running--;delete flight[id];pump();});
    })(jobs.shift());
   }
   if(!running && !jobs.length)waiters.splice(0).forEach(function(done){done();});
  }
  return {pending:function(){return !!(running || jobs.length);},run:function(ids){
   ids.forEach(function(id){if(!flight[id]){flight[id]=true;jobs.push(id);notify(id,{pending:true,summary:'等待探测…'});}});
   var done=new Promise(function(resolve){waiters.push(resolve);});pump();return done;
  }};
 }
});
