import { Builder, By, Browser, until } from "npm:selenium-webdriver@4.35.0";
import edge from "npm:selenium-webdriver@4.35.0/edge.js";

const FRONTEND = Deno.env.get('RT_FINAL_FRONTEND') || 'https://kaalflash12.github.io/reinos-tribais-online/';
const API = Deno.env.get('RT_FINAL_API') || 'https://reino-tribal-api.mestrederpg35.deno.net';
const PASSWORD = Deno.env.get('RT_FINAL_ADMIN_PASSWORD') || '';
const OUT = Deno.env.get('RT_FINAL_PROOF_DIR') || `${Deno.env.get('TEMP') || '.'}/RT90_ADMIN_PUBLIC_PROOF`;
const USERNAME = 'reinos_admin';
if (!PASSWORD) throw new Error('RT_FINAL_ADMIN_PASSWORD ausente.');
await Deno.mkdir(OUT,{recursive:true});
const proof={pass:false,frontend:FRONTEND,api:API,browser:'edge',checks:[],generated_at:new Date().toISOString()};
const pass=name=>proof.checks.push({name,pass:true});

const opts = new edge.Options();
opts.addArguments('--window-size=1440,1000','--no-first-run','--disable-features=EdgeFirstRunExperience','--disable-dev-shm-usage');
let driver;
try{
  driver = await new Builder().forBrowser(Browser.EDGE).setEdgeOptions(opts).build();
  await driver.manage().setTimeouts({pageLoad:60000,script:60000,implicit:0});
  await driver.get(`${FRONTEND}?rt90-admin=${Date.now()}`);

  await driver.wait(async()=>await driver.executeScript("return window.__RT_TURSO_BRIDGE__===true && window.ReinoTribalTurso?.version==='1.0.6-turso-recovery-complete'"),60000);
  pass('public final Turso bridge');
  await driver.wait(until.elementLocated(By.css('[data-entry-online]')),30000);
  await driver.findElement(By.css('[data-entry-online]')).click();
  const form=await driver.wait(until.elementLocated(By.css('#rt18-login-form')),30000);
  await driver.wait(until.elementIsVisible(form),30000);
  pass('public login UI visible');

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

  const shot=await driver.takeScreenshot();
  const raw=Uint8Array.from(atob(shot),c=>c.charCodeAt(0));
  await Deno.writeFile(`${OUT}/RT90_ADMIN_DASHBOARD_PUBLICO.png`,raw);
  pass('public admin screenshot captured');
  proof.pass=true;
}catch(e){
  proof.error=String(e?.stack||e);
  if(driver){try{const shot=await driver.takeScreenshot();const raw=Uint8Array.from(atob(shot),c=>c.charCodeAt(0));await Deno.writeFile(`${OUT}/RT90_ADMIN_FAILURE.png`,raw)}catch{}}
  throw e;
}finally{
  await Deno.writeTextFile(`${OUT}/PROVA_RT90_ADMIN_PUBLICO.json`,JSON.stringify(proof,null,2));
  if(driver)try{await driver.quit()}catch{}
}
console.log(JSON.stringify({pass:proof.pass,checks:proof.checks.length,browser:proof.browser}));
