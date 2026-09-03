import * as core from './v19_fullscope_engine.mjs';

const clone=v=>structuredClone(v);
const round2=v=>Math.round((Number(v)||0)*100)/100;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,Number(v)||0));
const pad=n=>String(n).padStart(2,'0');
const FIXED_BR_HOLIDAYS=new Set(['01-01','04-21','05-01','09-07','10-12','11-02','11-15','11-20','12-25']);
export const COMPLETE_ENGINE_VERSION='19.8.0-complete';
export const LEDGER_PERSISTENCE_COMPAT=core.LEDGER_PERSISTENCE_COMPAT;
export const TAX_REGIMES=core.TAX_REGIMES;

function uid(prefix){return `${prefix}-${crypto.randomUUID()}`;}
function holiday(date){return FIXED_BR_HOLIDAYS.has(`${pad(date.getUTCMonth()+1)}-${pad(date.getUTCDate())}`);}
function nextBusinessDay(iso){const d=new Date(iso);while(d.getUTCDay()===0||d.getUTCDay()===6||holiday(d))d.setUTCDate(d.getUTCDate()+1);return d.toISOString();}
function ledger(w,reason,from,to,amount,meta={}){amount=round2(amount);if(!(amount>0))return;const batch_id=uid('batch'),world_time=w.world_time;w.ledger.batches.push({batch_id,reason,world_time,meta});w.ledger.entries.push({entry_id:uid('le'),batch_id,account:from,amount:-amount,reason,world_time,meta});w.ledger.entries.push({entry_id:uid('le'),batch_id,account:to,amount,reason,world_time,meta});}
function playerLate(w){return Math.max(0,...w.government.tax_notices.filter(n=>n.owner_id===w.player.character_id&&n.status==='OPEN').map(n=>Number(n.days_late||0)));}
function refreshCredit(w){const p=w.player,tp=p.tax_profile??=( {regime:'MEI',risk_score:0,delinquency_days:0} );tp.base_credit_score??=Number(p.credit_score||650);const late=playerLate(w);tp.delinquency_days=late;tp.financing_penalty=round2(clamp(late/365*.12,0,.12));p.credit_score=Math.round(clamp(tp.base_credit_score-late*.65,300,850));tp.financing_restricted=late>=180||p.credit_score<400;return w;}
function upgrade(input){const w=input;w.engine_version=COMPLETE_ENGINE_VERSION;for(const row of w.government.tax_calendar||[])row.due_world=nextBusinessDay(row.due_world);for(const n of w.government.tax_notices||[])n.due_world=nextBusinessDay(n.due_world);refreshCredit(w);return w;}
function cyclesProcessed(w){return Math.floor(Number(w.macro?.days_processed||0)/30);}
function generateEnterpriseCycle(w,cycle){
  const active=(w.companies||[]).filter(c=>c.status==='ACTIVE'&&c.ownership!=='STATE').sort((a,b)=>a.company_id.localeCompare(b.company_id)).slice(0,25);
  for(const c of active){
    if(w.government.tax_notices.some(n=>n.tax_code==='ENTERPRISE'&&n.owner_id===c.company_id&&n.cycle===cycle))continue;
    const regime=TAX_REGIMES[c.tax_regime]||TAX_REGIMES.REAL,principal=round2(Math.max(1,Number(c.cash||0)*regime.rate/1200)),notice={notice_id:uid('tax'),owner_id:c.company_id,tax_code:'ENTERPRISE',cycle,principal,interest:0,fine:0,balance:principal,status:'OPEN',issued_world:w.world_time,due_world:nextBusinessDay(new Date(new Date(w.world_time).getTime()+5*86400000).toISOString()),days_late:0,regime:c.tax_regime};
    w.government.tax_notices.push(notice);
    if(Number(c.cash||0)>=principal){c.cash=round2(c.cash-principal);ledger(w,'ENTERPRISE_TAX',`company:${c.company_id}`,'treasury',principal,{company_id:c.company_id,regime:c.tax_regime,cycle});notice.balance=0;notice.status='PAID';notice.paid_world=w.world_time;w.finance.tax_payments.push({payment_id:uid('taxpay'),notice_id:notice.notice_id,owner_id:c.company_id,tax_code:'ENTERPRISE',amount:principal,world_time:w.world_time,cycle});}
  }
}
function afterAdvance(before,out){const w=upgrade(out.world),from=cyclesProcessed(before),to=cyclesProcessed(w);for(let cycle=from+1;cycle<=to;cycle++)generateEnterpriseCycle(w,cycle);w.macro.tax_revenue=round2(Number(w.ledger?.archive?.treasury_positive||0)+(w.ledger?.entries||[]).filter(e=>e.account==='treasury'&&e.amount>0).reduce((s,e)=>s+Number(e.amount||0),0));return {...out,world:w};}
function financingCommand(w,command){const late=playerLate(w),tp=w.player.tax_profile||{},score=Number(w.player.credit_score||650);if(late>=180||tp.financing_restricted||score<400)throw new Error('FINANCING_RESTRICTED_BY_TAX_RISK');const spread=Number(tp.financing_penalty||0)+Number(tp.risk_score||0)*.01;return {...command,rate:command.rate??Number(w.fx.policy_rate||.10)+.06+spread};}

export function createWorld(opts={}){return upgrade(core.createWorld(opts));}
export function tickWorld(input,opts={}){const before=upgrade(clone(input));return afterAdvance(before,core.tickWorld(before,opts));}
export function catchUpWorld(input,opts={}){const before=upgrade(clone(input));return afterAdvance(before,core.catchUpWorld(before,opts));}
export function applyAction(input,command={}){
  const w=upgrade(clone(input)),a=String(command.action||'').toLowerCase();let cmd=command;
  if(['borrow','pegar empréstimo','pegar emprestimo','mortgage','take_mortgage'].includes(a))cmd=financingCommand(w,command);
  let out=core.applyAction(w,cmd);out.world=upgrade(out.world);
  if(a==='card_purchase'){
    const card=out.world.finance.cards.find(c=>c.card_id===out.result?.card?.card_id),charge=card?.statement?.at(-1);if(charge){const installments=Math.max(1,Math.min(24,Math.trunc(Number(command.installments||1))));charge.installments=installments;charge.installment_amount=round2(charge.amount/installments);out.result.card=card;out.result.charge=charge;}
  }
  refreshCredit(out.world);return out;
}
export function auditWorld(input){const w=upgrade(clone(input)),a=core.auditWorld(w),calendarInvalid=(w.government.tax_calendar||[]).filter(x=>{const d=new Date(x.due_world);return d.getUTCDay()===0||d.getUTCDay()===6||holiday(d)}).length,noticeCalendarInvalid=(w.government.tax_notices||[]).filter(x=>{const d=new Date(x.due_world);return d.getUTCDay()===0||d.getUTCDay()===6||holiday(d)}).length;a.invalid_tax_calendar_dates=calendarInvalid;a.invalid_tax_notice_dates=noticeCalendarInvalid;a.ok=a.ok&&calendarInvalid===0&&noticeCalendarInvalid===0;return a;}
export function compactState(input){const w=upgrade(clone(input)),c=core.compactState(w);c.version=COMPLETE_ENGINE_VERSION;c.financial_and_tax.tax_record_count=w.government.tax_notices.length;c.financial_and_tax.enterprise_tax_paid=w.finance.tax_payments.filter(p=>p.tax_code==='ENTERPRISE').length;c.financial_and_tax.credit_score=w.player.credit_score;c.financial_and_tax.financing_penalty=w.player.tax_profile.financing_penalty;c.financial_and_tax.financing_restricted=w.player.tax_profile.financing_restricted;c.financial_and_tax.fixed_holiday_calendar=[...FIXED_BR_HOLIDAYS];return c;}
