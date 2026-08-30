require("vhd.lua")
VHD.addSearchPath("/DigiTerionMon")
VHD.addSearchPath("/DigiTerionMon/scripts")
require("ndb.lua")
local Bootstrap=require("scripts/bootstrap.lua")

local DB_NAME="gate17_358.ndb"
local SENTINEL="DIGITERION_GATE17_AUTORUN_V2"
local MISSION_ID="G17-MISSION-PERSIST"
local FACT_ID="G17-FACT-PERSIST"
local ROUTE_ID="G17-ROUTE-PERSIST"

local function childNodes(node)
  if node==nil then return {} end
  return NDB.getChildNodes(node) or {}
end

local function firstRecord(tracker)
  if tracker==nil or tracker.registros==nil then return nil end
  local list=childNodes(tracker.registros)
  return list[1]
end

local function fail(code,detail)
  showMessage("GATE17_FAIL|"..tostring(code).."|"..tostring(detail or ""))
end

local db=NDB.load(DB_NAME)
NDB.onReady(db,function()
  local phase=tostring(db.gate17Sentinel or "")

  if phase=="" then
    local ensured,res=Bootstrap.ensure(db)
    if not ensured then fail("ENSURE",res); return end
    local audit,status=Bootstrap.runtimeAudit(db)
    if not audit then fail("AUDIT1",status); return end

    local frTracker=Bootstrap.getTracker(db,"FRAGMENTOS")
    local npcTracker=Bootstrap.getTracker(db,"NPCS_ATIVOS")
    local orgTracker=Bootstrap.getTracker(db,"ESTADO_DAS_ORGANIZACOES")
    local fr=firstRecord(frTracker)
    local npc=firstRecord(npcTracker)
    local org=firstRecord(orgTracker)
    if fr==nil or npc==nil or org==nil then fail("SEED","fragment/npc/org missing"); return end

    local frKey=tostring(fr.recordKey or fr.canonicalPath or "")
    local npcKey=tostring(npc.recordKey or npc.canonicalId or "")
    local orgKey=tostring(org.recordKey or org.canonicalPath or "")
    if frKey=="" or npcKey=="" or orgKey=="" then fail("KEYS","empty canonical key"); return end

    local okBegin=pcall(function() NDB.beginUpdate(db) end)
    local f1,e1=Bootstrap.setFragmentState(db,frKey,{descoberto=true,obtido=true,portador="GATE17_PORTADOR",localAtual="GATE17_LOCAL",observacoes="GATE17_FRAGMENT_OK"})
    local m1,e2=Bootstrap.setMissionState(db,MISSION_ID,{nome="Missão Gate 17",objetivo="Persistir",estado="ativa",capitulo="G17",cena="F1",recompensa="OK",observacoes="GATE17_MISSION_OK"})
    local fa1,e3=Bootstrap.setFactState(db,FACT_ID,{fato="Fato persistente Gate17",fonte="autorun",descobertoEm="F1",publico=true,observacoes="GATE17_FACT_OK"})
    local n1,e4=Bootstrap.setNPCState(db,npcKey,{ativo=true,["local"]="GATE17_NPC_LOCAL",estado="ferido",relacao="aliado",ultimaCena="F1",observacoes="GATE17_NPC_OK"})
    local r1,e5=Bootstrap.setRouteState(db,ROUTE_ID,{origem="G17-A",destino="G17-B",estado="aberta",requisitos="nenhum",descoberto=true,observacoes="GATE17_ROUTE_OK"})
    local o1,e6=Bootstrap.setOrganizationState(db,orgKey,{descoberta=true,reputacao=17,hostilidade=3,contatos="GATE17_CONTATO",objetivos="GATE17_OBJ",recursos="GATE17_REC",missoesLiberadas="G17",fatosConhecidos="GATE17_ORG_OK"})
    if okBegin then pcall(function() NDB.endUpdate(db) end) end
    if not f1 or not m1 or not fa1 or not n1 or not r1 or not o1 then
      fail("WRITE",table.concat({tostring(e1),tostring(e2),tostring(e3),tostring(e4),tostring(e5),tostring(e6)},"|")); return
    end

    NDB.beginUpdate(db)
    db.gate17Sentinel=SENTINEL
    db.gate17PhaseOne="PASS"
    db.gate17Bootstrap=Bootstrap.VERSION
    db.gate17FragmentKey=frKey
    db.gate17NPCKey=npcKey
    db.gate17OrgKey=orgKey
    db.gate17TrackerToken=tostring(frTracker.persistenceToken or "")
    db.gate17Audit1=tostring(status)
    NDB.endUpdate(db)

    if tostring(db.gate17TrackerToken or "")=="" then fail("TOKEN1","empty tracker token"); return end
    showMessage("GATE17_PHASE1_PASS|"..tostring(status))
    return
  end

  if phase~=SENTINEL then fail("SENTINEL",phase); return end
  if tostring(db.gate17PhaseOne or "")~="PASS" then fail("PHASE1_FLAG",db.gate17PhaseOne); return end
  if tostring(db.gate17Bootstrap or "")~=Bootstrap.VERSION then fail("BOOTSTRAP_STORED",db.gate17Bootstrap); return end

  local audit,status=Bootstrap.runtimeAudit(db)
  if not audit then fail("AUDIT2",status); return end
  if tostring(db.bootstrapVersion or "")~=Bootstrap.VERSION then fail("BOOTSTRAP_REOPEN",db.bootstrapVersion); return end

  local frKey=tostring(db.gate17FragmentKey or "")
  local npcKey=tostring(db.gate17NPCKey or "")
  local orgKey=tostring(db.gate17OrgKey or "")
  local fr=Bootstrap.getPersistentState(db,"FRAGMENTOS",frKey)
  local mi=Bootstrap.getPersistentState(db,"MISSOES",MISSION_ID)
  local fa=Bootstrap.getPersistentState(db,"FATOS",FACT_ID)
  local np=Bootstrap.getPersistentState(db,"NPCS",npcKey)
  local ro=Bootstrap.getPersistentState(db,"ROTAS",ROUTE_ID)
  local og=Bootstrap.getPersistentState(db,"ORGANIZACOES",orgKey)
  local tr=Bootstrap.getTracker(db,"FRAGMENTOS")

  local checks={
    fr~=nil and fr.descoberto==true and fr.obtido==true and tostring(fr.portador or "")=="GATE17_PORTADOR" and tostring(fr.observacoes or "")=="GATE17_FRAGMENT_OK",
    mi~=nil and tostring(mi.estado or "")=="ativa" and tostring(mi.observacoes or "")=="GATE17_MISSION_OK",
    fa~=nil and fa.publico==true and tostring(fa.observacoes or "")=="GATE17_FACT_OK",
    np~=nil and np.ativo==true and tostring(np["local"] or "")=="GATE17_NPC_LOCAL" and tostring(np.estado or "")=="ferido" and tostring(np.observacoes or "")=="GATE17_NPC_OK",
    ro~=nil and ro.descoberto==true and tostring(ro.estado or "")=="aberta" and tostring(ro.observacoes or "")=="GATE17_ROUTE_OK",
    og~=nil and og.descoberta==true and tonumber(og.reputacao or -1)==17 and tonumber(og.hostilidade or -1)==3 and tostring(og.fatosConhecidos or "")=="GATE17_ORG_OK",
    tr~=nil and tostring(tr.persistenceToken or "")~="" and tostring(tr.persistenceToken or "")==tostring(db.gate17TrackerToken or "")
  }
  for i,v in ipairs(checks) do if not v then fail("CHECK"..tostring(i),status); return end end

  showMessage("GATE17_PHASE2_PASS|"..tostring(status))
end,function()
  showMessage("GATE17_NDB_OPEN_FAIL")
end)
