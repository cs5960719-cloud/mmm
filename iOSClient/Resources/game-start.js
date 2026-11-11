(function(){
if(window.__cdkStartLoop)return;window.__cdkStartLoop=true;
var server=__CDK_SERVER__,role=__CDK_ROLE__,selectedServer=false,selectedRole=false,roleAsked=false;
var t0=Date.now(),failed=false,enterFn=null,clickedAt=0,reentered=false,reloaded=false;
function patchShowPage(){
  if(window.__cdkShowPagePatched)return;
  if(typeof window.showPage!=='function')return;
  var orig=window.showPage;
  window.showPage=function(data,getId,callback){
    try{
      var dom=new DOMParser().parseFromString(data,'text/html');
      var bodyDom=dom.getElementById('body')||dom.body;
      var holder=document.getElementById('body');
      if(!holder)return orig.apply(this,arguments);
      holder.innerHTML=bodyDom.innerHTML;
      var styles=dom.getElementsByTagName('style');
      for(var i=0;i<styles.length;i++){var st=document.createElement('style');
        st.innerHTML=styles[i].innerHTML;
        document.getElementsByTagName('head')[0].appendChild(st);}
      var tags=dom.getElementsByTagName('script'),inner=[],outer=[];
      for(i=0;i<tags.length;i++){
        if(tags[i].src)outer.push(tags[i].src);else inner.push(tags[i].innerHTML);}
      var done=false,left=outer.length,guard=null;
      var finish=function(){
        if(done)return;done=true;
        if(guard)clearTimeout(guard);
        var code=inner.join('');
        if(code){try{window.eval(code);}catch(e){}}
        if(typeof callback==='function')callback();
      };
      if(!left){finish();return true;}
      guard=setTimeout(finish,10000);
      var oneDone=function(){if(--left<=0)finish();};
      for(i=0;i<outer.length;i++){
        var sc=document.createElement('script');
        sc.src=outer[i];sc.onload=oneDone;sc.onerror=oneDone;
        document.body.appendChild(sc);}
      return true;
    }catch(e){return orig.apply(this,arguments);}
  };
  window.__cdkShowPagePatched=true;
}
var timer=setInterval(function(){
  patchShowPage();
  try{
    if(!selectedServer&&typeof enter_game==='function'&&document.querySelector('#curDf a')){
      enterFn=enter_game;enterFn(server,2);selectedServer=true;clickedAt=Date.now();
    }
    var loadWrap=document.getElementById('loadWrap');
    if(enterFn&&loadWrap&&typeof window.load_engine!=='function'){
      var gap=Date.now()-clickedAt;
      if(!reentered&&gap>40000){
        reentered=true;enterFn(server,2);clickedAt=Date.now();
      }else if(reentered&&!reloaded&&gap>30000){
        reloaded=true;location.reload();return;
      }
    }
    if(window.ViewManager&&window.RoleMgr){var win=ViewManager.ins().getView('SelectRoleWin');
      if(win){if(role&&!selectedRole){RoleMgr.ins().sendEnterGame(role);selectedRole=true;}
        else if(!role&&!roleAsked){roleAsked=true;clearInterval(timer);
          window.__cdkStartLoop=false;if(window.CdkBridge)CdkBridge.needRole();return;}}}
    var em=window.EntityManager&&EntityManager.ins();var main=em&&em.getMainRole(0);
    if(main){var cur=(window.RoleMgr&&RoleMgr.ins().lastRoleID)||-1;
      if(!role||cur==role){clearInterval(timer);window.__cdkStartLoop=false;
        if(window.CdkBridge)CdkBridge.entered('');return;}}
  }catch(e){}
  if(!failed&&Date.now()-t0>180000){failed=true;
    if(window.CdkBridge)CdkBridge.fail('timeout');}
  if(failed&&Date.now()-t0>900000){clearInterval(timer);window.__cdkStartLoop=false;}
},800);})();
