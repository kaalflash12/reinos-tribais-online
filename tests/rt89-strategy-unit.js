import { normalizeSchedule, validateStrategyPayload } from '../api/strategy.js';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectThrow(fn, contains) {
  let thrown = null;
  try { fn(); } catch (error) { thrown = error; }
  assert(thrown, `Era esperado erro contendo: ${contains}`);
  assert(String(thrown.message).includes(contains), `Erro inesperado: ${thrown.message}`);
}

const build = validateStrategyPayload('build_upgrade', {
  village_id: 'v1', building: 'barracks', target_level: 4,
});
assert(build.village_id === 'v1' && build.building === 'barracks' && build.target_level === 4, 'build_upgrade inválido.');

const recruit = validateStrategyPayload('recruit_units', {
  village_id: 'v1', unit: 'spear', quantity: 50,
});
assert(recruit.unit === 'spear' && recruit.quantity === 50, 'recruit_units inválido.');

const attack = validateStrategyPayload('attack', {
  village_id: 'v1', target_village_id: 'v2', troops: { spear: 100, axe: 25, spy: 0 },
});
assert(attack.target_village_id === 'v2', 'attack sem alvo.');
assert(attack.troops.spear === 100 && attack.troops.axe === 25 && !('spy' in attack.troops), 'attack não normalizou tropas.');

const spy = validateStrategyPayload('spy', {
  village_id: 'v1', target_village_id: 'v2', spies: 12,
});
assert(spy.spies === 12, 'spy inválido.');

const support = validateStrategyPayload('support', {
  village_id: 'v1', target_village_id: 'ally-1', troops: { spear: 40, sword: 30 },
});
assert(support.troops.sword === 30, 'support inválido.');

const transfer = validateStrategyPayload('transfer_resources', {
  village_id: 'v1', target_village_id: 'v2', resources: { wood: 1000, clay: 500, iron: 250 },
});
assert(transfer.resources.wood === 1000 && transfer.resources.iron === 250, 'transfer_resources inválido.');

const deposit = validateStrategyPayload('collect_deposit', {
  village_id: 'v1', deposit_id: 'deposit-9',
});
assert(deposit.deposit_id === 'deposit-9', 'collect_deposit inválido.');

expectThrow(() => validateStrategyPayload('hack', { village_id: 'v1' }), 'Tipo de comando estratégico inválido');
expectThrow(() => validateStrategyPayload('build_upgrade', { village_id: 'v1', building: 'main', target_level: 0 }), 'target_level');
expectThrow(() => validateStrategyPayload('recruit_units', { village_id: 'v1', unit: 'spear', quantity: -1 }), 'quantity');
expectThrow(() => validateStrategyPayload('attack', { village_id: 'v1', target_village_id: 'v2', troops: {} }), 'pelo menos uma unidade');
expectThrow(() => validateStrategyPayload('transfer_resources', { village_id: 'v1', target_village_id: 'v2', resources: {} }), 'conter recursos');

const now = Date.UTC(2026, 7, 26, 12, 0, 0);
assert(normalizeSchedule('', now) === new Date(now).toISOString(), 'Agenda vazia deveria usar agora.');
const future = new Date(now + 60_000).toISOString();
assert(normalizeSchedule(future, now) === future, 'Agenda futura foi alterada.');
expectThrow(() => normalizeSchedule(new Date(now + 31 * 86_400_000).toISOString(), now), '30 dias');

console.log('RT89_STRATEGY_UNIT_PASS');
