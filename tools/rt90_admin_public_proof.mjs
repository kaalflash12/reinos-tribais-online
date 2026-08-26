import { Builder, By, Browser, until } from "npm:selenium-webdriver@4.35.0";
import edge from "npm:selenium-webdriver@4.35.0/edge.js";

const FRONTEND = Deno.env.get('RT_FINAL_FRONTEND') || 'https://kaalflash12.github.io/reinos-tribais-online/';
const API = Deno.env.get('RT_FINAL_API') || 'https://reino-tribal-api.mestrederpg35.deno.net';
const PASSWORD = Deno.env.get('RT_FINAL_ADMIN_PASSWORD') || '';
const VALIDATE_ONLY = Deno.env.get('RT90_VALIDATE_ONLY') === '1';
const OUT = Deno.env.get('RT_FINAL_PROOF_DIR') || `${Deno.env.get('TEMP') || '.'}/RT90_ADMIN_PUBLIC_PROOF`;
const USERNAME = 'reinos_admin';
if (!PASSWORD && !VALIDATE_ONLY) throw new Error('RT_FINAL_ADMIN_PASSWORD ausente.');
await Deno.mkdir(OUT,{recursive:true});
const proof={pass:false,validate_only:VALIDATE_ONLY,frontend:FRONTEND,api:API,browser:'edge',checks:[],generated_at:new Date().toISOString()};
const pass=name=>proof.checks.push({name,pass:true});
async function screenshot(driver,name){const shot=await driver.takeScreenshot();const raw=Uint8Array.from(atob(shot),c=>c.charCodeAt(0));await Deno.writeFile(`${OUT}/${name}`,raw)}

const decoder=new TextDecoder();
async function exists(path){try{await Deno.stat(path);return true}catch{return false}}
async function edgeVersionFromExe(edgeExe){
  const r=await new Deno.Command('powershell.exe',{
    args:['-NoProfile','-ExecutionPolicy','Bypass','-Command','(Get-Item -LiteralPath $env:RT90_EDGE_EXE).VersionInfo.ProductVersion'],
    env:{RT90_EDGE_EXE:edgeExe},stdout:'piped',stderr:'piped'
  }).output();
  const text=(decoder.decode(r.stdout)+' '+decoder.decode(r.stderr)).trim();
  const m=text.match(/\b(\d+\.\d+\.\d+\.\d+)\b/);
  if(!r.success||!m)throw new Error(`Não foi possível detectar a versão do Edge em ${edgeExe}: ${text}`);
  return m[1];
}
async function detectEdge(){
  const candidates=[];
  const pf86=Deno.env.get('PROGRAMFILES(X86)');
  const pf=Deno.env.get('PROGRAMFILES');
  const local=Deno.env.get('LOCALAPPDATA');
  if(pf86)candidates.push(`${pf86}\\Microsoft\\Edge\\Application\\msedge.exe`);
  if(pf)candidates.push(`${pf}\\Microsoft\\Edge\\Application\\msedge.exe`);
  if(local)candidates.push(`${local}\\Microsoft\\Edge\\Application\\msedge.exe`);
  for(const exe of candidates){if(await exists(exe))return {exe,version:await edgeVersionFromExe(exe)}}
  throw new Error('Microsoft Edge não encontrado nos caminhos padrão do Windows.');
}
async function curlDownload(url,out){
  const r=await new Deno.Command('curl.exe',{
    args:['--fail','--silent','--show-error','--location','--http1.1','--tlsv1.2','--retry','3','--retry-all-errors','--connect-timeout','20','--max-time','180','--output',out,url],
    stdout:'piped',stderr:'piped'
  }).output();
  if(!r.success||!(await exists(out))){
    const err=(decoder.decode(r.stderr)||decoder.decode(r.stdout)).trim();
    throw new Error(`download falhou: ${url} :: ${err}`);
  }
}
async function resolveEdgeDriver(){
  const explicit=Deno.env.get('RT90_EDGE_DRIVER');
  if(explicit&&await exists(explicit))return {path:explicit,source:'RT90_EDGE_DRIVER',edge:null};
  if(Deno.build.os!=='windows')return {path:null,source:'selenium-manager-non-windows',edge:null};

  const edgeInfo=await detectEdge();
  const dir=await Deno.makeTempDir({prefix:'rt90-msedgedriver-'});
  const zip=`${dir}\\edgedriver_win64.zip`;
  const urls=[
    `https://msedgedriver.microsoft.com/${edgeInfo.version}/edgedriver_win64.zip`,
    `https://msedgedriver.azureedge.net/${edgeInfo.version}/edgedriver_win64.zip`
  ];
  let last;
  let source='';
  for(const url of urls){
    try{await curlDownload(url,zip);source=url;last=null;break}catch(e){last=e;try{await Deno.remove(zip)}catch{}}
  }
  if(last)throw new Error(`Não foi possível baixar o EdgeDriver ${edgeInfo.version} por nenhum endpoint oficial/fallback. ${String(last?.message||last)}`);

  const x=await new Deno.Command('powershell.exe',{
    args:['-NoProfile','-ExecutionPolicy','Bypass','-Command','Expand-Archive -LiteralPath $env:RT90_EDGE_ZIP -DestinationPath $env:RT90_EDGE_DIR -Force'],
    env:{RT90_EDGE_ZIP:zip,RT90_EDGE_DIR:dir},stdout:'piped',stderr:'piped'
  }).output();
  if(!x.success)throw new Error('Falha extraindo EdgeDriver: '+decoder.decode(x.stderr));
  const driverPath=`${dir}\\msedgedriver.exe`;
  if(!(await exists(driverPath)))throw new Error('msedgedriver.exe não apareceu após a extração.');
  return {path:driverPath,source,edge:edgeInfo};
}

const opts = new edge.Options();
opts.addArguments('--window-size=1440,1000','--no-first-run','--disable-features=EdgeFirstRunExperience','--disable-dev-shm-usage');
if(VALIDATE_ONLY)opts.addArguments('--headless=new');
let driver;
try{
  const driverInfo=await resolveEdgeDriver();
  if(driverInfo.edge){
    proof.edge_version=driverInfo.edge.version;
    proof.edge_binary=driverInfo.edge.exe;
    proof.edgedriver_source=driverInfo.source;
    pass('matching EdgeDriver resolved without Selenium Manager');
  }
  let builder=new Builder().forBrowser(Browser.EDGE).setEdgeOptions(opts);
  if(driverInfo.path)builder=builder.setEdgeService(new edge.ServiceBuilder(driverInfo.path));
  driver = await builder.build();
  await driver.manage().setTimeouts({pageLoad:60000,script:60000,implicit:0});
  await driver.get(`${FRONTEND}?rt90-admin=${Date.now()}`);

  await driver.wait(async()=>await driver.executeScript("return window.__RT_TURSO_BRIDGE__===true && window.ReinoTribalTurso?.version==='1.0.6-turso-recovery-complete'"),60000);
  pass('public final Turso bridge');
  await driver.wait(until.elementLocated(By.css('[data-entry-online]')),30000);
  await driver.findElement(By.css('[data-entry-online]')).click();
  const form=await driver.wait(until.elementLocated(By.css('#rt18-login-form')),30000);
  await driver.wait(until.elementIsVisible(form),30000);
  pass('public login UI visible');

  const legacyBefore=await driver.executeScript("return performance.getEntriesByType('resource').map(x=>x.name).filter(x=>x.includes('rlyiwlwzrdgvcwawrnpl.supabase.co'))");
  if(Array.isArray(legacyBefore)&&legacyBefore.length)throw new Error('Tráfego Supabase legado detectado antes do login: '+legacyBefore.slice(0,5).join(', '));
  pass('zero legacy Supabase network before admin login');

  if(VALIDATE_ONLY){
    await screenshot(driver,'RT90_VALIDATE_ONLY_PUBLIC_LOGIN.png');
    pass('selenium edge runtime operational');
    proof.pass=true;
  }else{
    const user=await driver.findElement(By.css('#rt18-login-form [name=email]'));
    const pwd=await driver.findElement(By.css('#rt18-login-form [name=password]'));
    await user.clear(); await user.sendKeys(USERNAME);
    await pwd.clear(); await pwd.sendKeys(PASSWORD);
    await driver.findElement(By.css('#rt18-login-form button[type=submit]')).click();

    await driver.wait(async()=>await driver.executeScript("return !!sessionStorage.getItem('rt60_admin_token')"),60000);
    pass('real admin session created by public UI');
    const shell=await driver.wait(until.elementLocated(By.css('.rt60-admin-shell')),60000);
    await driver.wait(until.elementIsVisible(shell),30000);
    pass('real admin dashboard rendered');
    const header=await driver.findElement(By.css('.rt60-admin-top')).getText();
    if(!header.includes(USERNAME))throw new Error('Dashboard não identifica reinos_admin.');
    pass('dashboard identifies reinos_admin');
    if(!(await driver.findElements(By.css('[data-admin-panel="overview"]'))).length)throw new Error('Painel overview ADM ausente.');
    pass('admin overview exists');

    const status=await driver.executeAsyncScript(`
      const done=arguments[arguments.length-1];
      const token=sessionStorage.getItem('rt60_admin_token');
      fetch(${JSON.stringify(API)}+'/api/reino',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({action:'admin_status'}),cache:'no-store'})
        .then(async r=>{let d={};try{d=await r.json()}catch{};done({ok:r.ok,status:r.status,data:d})})
        .catch(e=>done({ok:false,status:0,error:String(e)}));
    `);
    if(!status?.ok || !status?.data?.ok)throw new Error('admin_status público autenticado falhou: '+JSON.stringify(status));
    pass('authenticated admin_status from public browser');

    const legacyNet=await driver.executeScript("return performance.getEntriesByType('resource').map(x=>x.name).filter(x=>x.includes('rlyiwlwzrdgvcwawrnpl.supabase.co'))");
    if(Array.isArray(legacyNet)&&legacyNet.length)throw new Error('Tráfego Supabase legado detectado: '+legacyNet.slice(0,5).join(', '));
    pass('zero legacy Supabase network');

    await screenshot(driver,'RT90_ADMIN_DASHBOARD_PUBLICO.png');
    pass('public admin screenshot captured');
    proof.pass=true;
  }
}catch(e){
  proof.error=String(e?.stack||e);
  if(driver){try{await screenshot(driver,'RT90_ADMIN_FAILURE.png')}catch{}}
  throw e;
}finally{
  await Deno.writeTextFile(`${OUT}/PROVA_RT90_ADMIN_PUBLICO.json`,JSON.stringify(proof,null,2));
  if(driver)try{await driver.quit()}catch{}
}
console.log(JSON.stringify({pass:proof.pass,validate_only:proof.validate_only,checks:proof.checks.length,browser:proof.browser}));
