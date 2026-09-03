import crypto from 'node:crypto';
import * as base from './v19_engine_patched.mjs';

const clone=v=>structuredClone(v);
const round2=v=>Math.round((Number(v)||0)*100)/100;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,Number(v)||0));
const uid=p=>`${p}-${crypto.randomUUID()}`;
const dayMs=86400000;

export const LEDGER_PERSISTENCE_COMPAT=base.LEDGER_PERSISTENCE_COMPAT;
export const FULL_SCOPE_VERSION='19.8.0-fullscope';
export const TAX_REGIMES={
  MEI:{rate:.06,label:'MEI'},
  SIMPLES:{rate:.10,label:'Simples Nacional'},
  PRESUMIDO:{rate:.135,label:'Lucro Presumido'},
  REAL:{rate:.15,label:'Lucro Real'},
};

function ledger(world,reason,from,to,amount,meta={}){
  amount=round2(amount);
  if(!(amount>0))return null;
  world.ledger??={batches:[],entries:[]};world.ledger.batches??=[];world.ledger.entries??=[];
  const batch_id=uid('batch'),world_time=world.world_time;
  world.ledger.batches.push({batch_id,reason,world_time,meta});
  world.ledger.entries.push({entry_id:uid('le'),batch_id,account:from,amount:-amount,reason,world_time,meta});
  world.ledger.entries.push({entry_id:uid('le'),batch_id,account:to,amount,reason,world_time,meta});
  return batch_id;
}
function liquid(p){return round2((p.cash||0)+(p.bank||0));}
function spend(world,p,amount,to,reason,meta={}){
  amount=round2(amount);if(!(amount>0))throw new Error('AMOUNT_REQUIRED');if(liquid(p)<amount)throw new Error('INSUFFICIENT_LIQUID_FUNDS');
  const cash=Math.min(round2(p.cash||0),amount),bank=round2(amount-cash);
  if(cash){p.cash=round2(p.cash-cash);ledger(world,`$${reason}:CASH`,`cash:${p.character_id}`,to,cash,meta)}
  if(bank){p.bank=round2(p.bank-bank);ledger(world,`$${reason}:BANK`,`bank:${p.character_id}`,to,bank,meta)}
}
function creditBank(world,p,amount,from,reason,meta={}){amount=round2(amount);p.bank=round2((p.bank||0)+amount);ledger(world,reason,from,`bank:${p.character_id}`,amount,meta);}
function daysBetween(a,b){return Math.max(0,Math.floor((new Date(b)-new Date(a))/dayMs));}
function nextDate(from,days){return new Date(new Date(from).getTime()+days*dayMs).toISOString();}
function companySize(c){const h=Number(c.employees?.length||0),cash=Number(c.cash||0);return h>=100||cash>=1e6?'LARGE':h>=40||cash>=300000?'MEDIUM':h>=10||cash>=80000?'SMALL':'MICRO';}

function ensure(world){
  const w=world;
  w.engine_version=FULL_SCOPE_VERSION;
  w.finance??={};
  w.finance.cards??=[];
  w.finance.investments??=[];
  w.finance.insurance??=[];
  w.finance.claims??=[];
  w.finance.insurance_policies??=clone(w.finance.insurance);
  w.finance.insurance_claims??=clone(w.finance.claims);
  w.finance.ownership_tax_history??=[];
  w.finance.tax_payments??=[];
  w.finance.mortgages??=[];
  w.government??={};
  w.government.tax_calendar??=[];
  w.government.tax_notices??=[];
  w.government.tax_foreclosure_rules??={grace_days:90,notice_after_days:15,foreclosure_after_days:180,automatic_company_block:false};
  w.government.tax_regimes??=clone(TAX_REGIMES);
  w.player.tax_profile??={regime:'MEI',risk_score:0,delinquency_days:0};
  w.player.vehicles??=[];
  w.macro??={days_processed:0,br_population:221000000,demand_by_quintile:[1,1,1,1,1],tax_revenue:0,last_cycle_world:null};
  w.fx.liquidity=Number.isFinite(Number(w.fx.liquidity))?Number(w.fx.liquidity):1;
  w.fx.trade_balance=Number.isFinite(Number(w.fx.trade_balance))?Number(w.fx.trade_balance):0;
  w.fx.tourism_index=Number.isFinite(Number(w.fx.tourism_index))?Number(w.fx.tourism_index):1;
  w.fx.parallel_premium=Number.isFinite(Number(w.fx.parallel_premium))?Number(w.fx.parallel_premium):.08;
  for(const c of w.companies||[]){c.size=companySize(c);c.tax_regime??=(c.ownership==='STATE'?'REAL':c.size==='MICRO'?'MEI':c.size==='SMALL'?'SIMPLES':c.size==='MEDIUM'?'PRESUMIDO':'REAL');}
  if(!w.government.tax_calendar.length){
    const baseDate=w.world_time||new Date().toISOString();
    w.government.tax_calendar.push(
      {tax_code:'PERSONAL_INCOME',cadence:'MONTHLY',due_world:nextDate(baseDate,5),weekend_adjustment:'NEXT_BUSINESS_DAY'},
      {tax_code:'PROPERTY',cadence:'ANNUAL',due_world:nextDate(baseDate,30),weekend_adjustment:'NEXT_BUSINESS_DAY'},
      {tax_code:'VEHICLE',cadence:'ANNUAL',due_world:nextDate(baseDate,35),weekend_adjustment:'NEXT_BUSINESS_DAY'},
      {tax_code:'ENTERPRISE',cadence:'MONTHLY',due_world:nextDate(baseDate,10),weekend_adjustment:'NEXT_BUSINESS_DAY'}
    );
  }
  if(!w.government.tax_notices.some(n=>n.owner_id===w.player.character_id&&n.tax_code==='PERSONAL_INCOME')){
    w.government.tax_notices.push({notice_id:uid('tax'),owner_id:w.player.character_id,tax_code:'PERSONAL_INCOME',principal:10,interest:0,fine:0,balance:10,status:'OPEN',issued_world:w.world_time,due_world:nextDate(w.world_time,5),days_late:0});
  }
  return w;
}

function refreshAliases(w){w.finance.insurance_policies=clone(w.finance.insurance);w.finance.insurance_claims=clone(w.finance.claims);return w;}
function noticeTotal(n){return round2(Number(n.principal||0)+Number(n.interest||0)+Number(n.fine||0));}
function accrueTaxes(w,days){
  for(const n of w.government.tax_notices){
    if(n.status!=='OPEN')continue;
    const late=Math.max(0,daysBetween(n.due_world,w.world_time));n.days_late=late;
    n.interest=round2(Number(n.principal||0)*.00033*late);
    n.fine=round2(Number(n.principal||0)*Math.min(.20,.0033*late));
    n.balance=noticeTotal(n);
  }
  const open=w.government.tax_notices.filter(n=>n.owner_id===w.player.character_id&&n.status==='OPEN');
  w.player.tax_profile.delinquency_days=Math.max(0,...open.map(n=>n.days_late||0));
  w.player.tax_profile.risk_score=clamp(open.reduce((s,n)=>s+(n.days_late||0)/30,0),0,10);
}
function accrueCards(w,days){
  for(const c of w.finance.cards){
    if(c.status!=='ACTIVE'||!(c.balance>0))continue;
    const daily=(Number(c.apr||.18)/365)*days;const interest=round2(c.balance*daily);
    if(interest>0){c.balance=round2(c.balance+interest);c.interest_accrued=round2((c.interest_accrued||0)+interest);ledger(w,'CARD_INTEREST',`card_interest:${c.card_id}`,`card_receivable:${c.card_id}`,interest,{card_id:c.card_id});}
  }
}
function accrueInvestments(w,days){for(const i of w.finance.investments){if(i.status!=='ACTIVE')continue;const rate=Number(i.annual_yield??.08),gain=round2(Number(i.value||0)*(rate/365)*days);i.value=round2(Number(i.value||0)+gain);i.yield_accrued=round2((i.yield_accrued||0)+gain);}}
function macroCycle(w,days){
  if(days<=0)return;
  w.macro.days_processed+=days;
  const inf=Number(w.fx.inflation||0),rate=Number(w.fx.policy_rate||0);
  w.fx.liquidity=round2(clamp(Number(w.fx.liquidity||1)+(rate<.12?.002:-.002)*days,.5,1.8));
  w.fx.trade_balance=round2(Number(w.fx.trade_balance||0)+(Number(w.fx.rates?.USD||.19)-.19)*1000*days);
  w.fx.tourism_index=round2(clamp(Number(w.fx.tourism_index||1)+(inf<.08?.001:-.0015)*days,.5,1.6));
  w.fx.parallel_premium=round2(clamp(Number(w.fx.parallel_premium||.08)+(inf-.04)*.01*days,0,.5));
  w.macro.demand_by_quintile=[.78,.88,1,1.12,1.24].map((x,i)=>round2(clamp(x*(1-inf*.8)*(1+(w.fx.liquidity-1)*.15)+(i-2)*.002*days,.4,1.8)));
  for(const c of w.companies||[]){c.size=companySize(c);c.demand_index=round2(clamp((c.demand_index||1)*(w.macro.demand_by_quintile[(c.company_id.length+c.employees.length)%5]||1),.35,2.5));}
  const before=Math.floor((w.macro.days_processed-days)/30),after=Math.floor(w.macro.days_processed/30);
  for(let k=before+1;k<=after;k++)w.environment.disasters.push({disaster_id:uid('disaster'),type:k%2?'FLOOD':'DROUGHT',severity:2+(k%4),world_time:w.world_time,status:'RESOLVED_SIMULATION'});
  w.macro.last_cycle_world=w.world_time;
}
function fiscalRevenue(w){const a=w.ledger?.archive||{};return round2(Number(a.treasury_positive||0)+(w.ledger?.entries||[]).filter(e=>e.account==='treasury'&&e.amount>0).reduce((s,e)=>s+Number(e.amount||0),0));}
function afterTimeAdvance(before,out){const w=ensure(out.world),days=Math.max(0,daysBetween(before.world_time,w.world_time));macroCycle(w,days);accrueTaxes(w,days);accrueCards(w,days);accrueInvestments(w,days);w.macro.tax_revenue=fiscalRevenue(w);refreshAliases(w);return {...out,world:w};}

export function createWorld(opts={}){return refreshAliases(ensure(base.createWorld(opts)));}
export function tickWorld(input,opts={}){const before=ensure(clone(input)),out=base.tickWorld(before,opts);return afterTimeAdvance(before,out);}
export function catchUpWorld(input,opts={}){const before=ensure(clone(input)),out=base.catchUpWorld(before,opts);return afterTimeAdvance(before,out);}

function result(w,command,payload){refreshAliases(w);w.macro.tax_revenue=fiscalRevenue(w);return {world:w,result:payload,ok:true};}
function findPlayer(w,aid){if(aid!==w.player.character_id)throw new Error('FULLSCOPE_PLAYER_ACTION_REQUIRED');return w.player;}
function cardFor(w,p,command){let c=w.finance.cards.find(x=>x.card_id===command.card_id&&x.owner_id===p.character_id);if(!c&&command.create_if_missing!==false){c={card_id:uid('card'),owner_id:p.character_id,issuer:command.issuer||'Banco Comercial',limit:round2(command.limit||1500),balance:0,apr:Number(command.apr??.18),interest_accrued:0,status:'ACTIVE',statement:[]};w.finance.cards.push(c)}return c;}
function ownershipValue(w,p,type,assetId,command){if(command.asset_value!=null)return round2(command.asset_value);if(type==='PROPERTY'){const x=w.property.properties.find(v=>v.property_id===assetId&&v.owner_id===p.character_id);if(!x)throw new Error('PROPERTY_NOT_OWNED');return round2(x.value||0)}if(type==='VEHICLE'){const x=p.vehicles.find(v=>v.vehicle_id===assetId);if(!x)throw new Error('VEHICLE_NOT_OWNED');return round2(x.value||0)}if(type==='ENTERPRISE'){const x=w.companies.find(v=>v.company_id===assetId&&v.owners?.includes(p.character_id));if(!x)throw new Error('ENTERPRISE_NOT_OWNED');return round2(Math.max(0,x.cash-x.debt))}throw new Error('OWNERSHIP_TAX_TYPE');}

export function applyAction(input,command={}){
  const w=ensure(clone(input)),a=String(command.action||'').toLowerCase(),aid=command.actor_id||w.player.character_id,p=findPlayer(w,aid);
  if(a==='repay'||a==='repay_loan'||a==='pay_loan'){
    const loan=w.finance.loans.find(l=>l.loan_id===command.loan_id&&l.borrower_id===aid&&l.status==='ACTIVE');if(!loan)throw new Error('LOAN_NOT_FOUND');const amount=round2(Math.min(Number(command.amount||loan.balance),loan.balance));spend(w,p,amount,'bank_reserve','LOAN_REPAYMENT',{loan_id:loan.loan_id});loan.balance=round2(loan.balance-amount);if(loan.balance<=.001)loan.status='PAID';return result(w,command,{loan,amount});
  }
  if(a==='mortgage'||a==='take_mortgage'){
    const prop=w.property.properties.find(x=>x.property_id===command.property_id);if(!prop)throw new Error('PROPERTY_NOT_FOUND');const price=round2(command.price??prop.value),down=round2(command.down_payment??price*.2),principal=round2(price-down);spend(w,p,down,`property_owner:${prop.owner_id}`,'MORTGAGE_DOWNPAYMENT',{property_id:prop.property_id});const m={loan_id:uid('mortgage'),borrower_id:aid,property_id:prop.property_id,principal,balance:principal,rate:Number(command.rate??w.fx.policy_rate+.035),installments:Number(command.installments||240),status:'ACTIVE',kind:'MORTGAGE'};w.finance.loans.push(m);w.finance.mortgages.push(m.loan_id);ledger(w,'MORTGAGE_FINANCE','bank_reserve',`property_owner:${prop.owner_id}`,principal,{property_id:prop.property_id});prop.owner_id=aid;if(!p.properties.includes(prop.property_id))p.properties.push(prop.property_id);return result(w,command,{mortgage:m,property:prop,down_payment:down});
  }
  if(a==='change_tax_regime'){
    const regime=String(command.regime||'').toUpperCase();if(!TAX_REGIMES[regime])throw new Error('INVALID_TAX_REGIME');if(command.company_id){const c=w.companies.find(x=>x.company_id===command.company_id&&x.owners?.includes(aid));if(!c)throw new Error('OWNER_REQUIRED');c.tax_regime=regime;return result(w,command,{company_id:c.company_id,regime})}p.tax_profile.regime=regime;return result(w,command,{regime});
  }
  if(a==='pay_official_tax'){
    let n=w.government.tax_notices.find(x=>x.notice_id===command.notice_id&&x.owner_id===aid&&x.status==='OPEN');if(!n)n=w.government.tax_notices.find(x=>x.owner_id===aid&&x.tax_code===String(command.tax_code||'PERSONAL_INCOME').toUpperCase()&&x.status==='OPEN');if(!n)throw new Error('TAX_NOTICE_NOT_FOUND');const amount=round2(Math.min(Number(command.amount||n.balance),n.balance));spend(w,p,amount,'treasury','OFFICIAL_TAX_PAYMENT',{notice_id:n.notice_id,tax_code:n.tax_code});n.balance=round2(n.balance-amount);if(n.balance<=.001){n.status='PAID';n.paid_world=w.world_time}w.finance.tax_payments.push({payment_id:uid('taxpay'),notice_id:n.notice_id,tax_code:n.tax_code,amount,world_time:w.world_time});return result(w,command,{notice:n,amount});
  }
  if(a==='card_purchase'){
    const c=cardFor(w,p,command);if(!c||c.status!=='ACTIVE')throw new Error('CARD_NOT_FOUND');const amount=round2(command.amount||0);if(!(amount>0)||c.balance+amount>c.limit)throw new Error('CARD_LIMIT');c.balance=round2(c.balance+amount);const charge={charge_id:uid('charge'),merchant:command.merchant||'merchant',amount,world_time:w.world_time};c.statement.push(charge);ledger(w,'CARD_PURCHASE',`card_issuer:${c.card_id}`,`merchant:${charge.merchant}`,amount,{card_id:c.card_id});return result(w,command,{card:c,charge});
  }
  if(a==='pay_card_bill'){
    const c=cardFor(w,p,{...command,create_if_missing:false});if(!c)throw new Error('CARD_NOT_FOUND');const amount=round2(Math.min(Number(command.amount||c.balance),c.balance));spend(w,p,amount,`card_issuer:${c.card_id}`,'CARD_PAYMENT',{card_id:c.card_id});c.balance=round2(c.balance-amount);return result(w,command,{card:c,amount});
  }
  if(a==='invest'){
    const amount=round2(command.amount||0);spend(w,p,amount,'investment_pool','INVESTMENT_PURCHASE',{instrument:command.instrument||'BOND'});const investment={investment_id:uid('investment'),owner_id:aid,instrument:command.instrument||'BOND',principal:amount,value:amount,annual_yield:Number(command.annual_yield??.08),liquidity:command.liquidity||'DAILY',yield_accrued:0,status:'ACTIVE',world_time:w.world_time};w.finance.investments.push(investment);return result(w,command,{investment});
  }
  if(a==='redeem_investment'){
    const i=w.finance.investments.find(x=>x.investment_id===command.investment_id&&x.owner_id===aid&&x.status==='ACTIVE');if(!i)throw new Error('INVESTMENT_NOT_FOUND');const amount=round2(Math.min(Number(command.amount||i.value),i.value));creditBank(w,p,amount,'investment_pool','INVESTMENT_REDEMPTION',{investment_id:i.investment_id});i.value=round2(i.value-amount);if(i.value<=.001)i.status='REDEEMED';return result(w,command,{investment:i,amount});
  }
  if(a==='buy_insurance'){
    const premium=round2(command.premium||30),coverage=round2(command.coverage||500),deductible=round2(command.deductible||20),type=command.type||'HEALTH';spend(w,p,premium,'insurance_pool','INSURANCE_PREMIUM',{type});const policy={policy_id:uid('policy'),policyholder_id:aid,type,premium,coverage,deductible,status:'ACTIVE',paid_through_world:nextDate(w.world_time,30),created_world:w.world_time};w.finance.insurance.push(policy);return result(w,command,{policy});
  }
  if(a==='pay_insurance_premium'){
    const policy=w.finance.insurance.find(x=>x.policy_id===command.policy_id&&x.policyholder_id===aid&&x.status==='ACTIVE');if(!policy)throw new Error('POLICY_NOT_FOUND');const amount=round2(command.amount??policy.premium);spend(w,p,amount,'insurance_pool','INSURANCE_PREMIUM',{policy_id:policy.policy_id});policy.paid_through_world=nextDate(policy.paid_through_world||w.world_time,30);return result(w,command,{policy,amount});
  }
  if(a==='file_insurance_claim'){
    const policy=w.finance.insurance.find(x=>x.policy_id===command.policy_id&&x.policyholder_id===aid&&x.status==='ACTIVE');if(!policy)throw new Error('POLICY_NOT_FOUND');const loss=round2(command.loss||100),payout=round2(Math.min(policy.coverage,Math.max(0,loss-policy.deductible)));creditBank(w,p,payout,'insurance_pool','INSURANCE_CLAIM',{policy_id:policy.policy_id});const claim={claim_id:uid('claim'),policy_id:policy.policy_id,policyholder_id:aid,loss,payout,status:'PAID',world_time:w.world_time};w.finance.claims.push(claim);return result(w,command,{claim});
  }
  if(a==='pay_ownership_tax'){
    const type=String(command.type||'PROPERTY').toUpperCase(),assetId=command.asset_id,assetValue=ownershipValue(w,p,type,assetId,command),rate=type==='PROPERTY'?.01:type==='VEHICLE'?.025:.015,amount=round2(command.amount??assetValue*rate);spend(w,p,amount,'treasury',`${type}_TAX`,{asset_id:assetId});const row={payment_id:uid('ownertax'),owner_id:aid,type,asset_id:assetId,asset_value:assetValue,rate,amount,world_time:w.world_time};w.finance.ownership_tax_history.push(row);return result(w,command,{payment:row});
  }
  const out=base.applyAction(w,command);out.world=ensure(out.world);refreshAliases(out.world);return out;
}

export function auditWorld(input){const w=ensure(clone(input)),a=base.auditWorld(w);const invalidCards=w.finance.cards.filter(c=>c.balance<-.001||c.balance>c.limit+.001).length,invalidInvestments=w.finance.investments.filter(i=>i.value<-.001).length,invalidNotices=w.government.tax_notices.filter(n=>n.balance<-.001).length,invalidRegimes=w.companies.filter(c=>!TAX_REGIMES[c.tax_regime]).length;a.invalid_cards=invalidCards;a.invalid_investments=invalidInvestments;a.invalid_tax_notices=invalidNotices;a.invalid_tax_regimes=invalidRegimes;a.ok=a.ok&&invalidCards===0&&invalidInvestments===0&&invalidNotices===0&&invalidRegimes===0;return a;}
export function compactState(input){const w=ensure(clone(input)),c=base.compactState(w);c.version=FULL_SCOPE_VERSION;c.financial_and_tax={cards:w.finance.cards,investments:w.finance.investments,insurance_policies:w.finance.insurance,insurance_claims:w.finance.claims,ownership_tax_history:w.finance.ownership_tax_history,tax_payments:w.finance.tax_payments,tax_calendar:w.government.tax_calendar,tax_notices:w.government.tax_notices,tax_profile:w.player.tax_profile,mortgages:w.finance.mortgages,macro:{...w.macro,liquidity:w.fx.liquidity,trade_balance:w.fx.trade_balance,tourism_index:w.fx.tourism_index,parallel_premium:w.fx.parallel_premium},tax_regimes:w.government.tax_regimes};return c;}
