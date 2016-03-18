--[[ TermostatoVirtual
	Dispositivo virtual
	autoTuneButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

local tuneTime = 3600    -- segundos que dura la pruena de calentamiento

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
-- obtener id del termostato
local idLabel = fibaro:get(fibaro:getSelfId(), 'ui.idLabel.value')
local p2 = string.find(idLabel, ' Panel')
local thermostatId = tonumber(string.sub(idLabel, 13, p2))
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
mode[3]='CALIBRADO_F1'; mode[4]='CALIBRADO_F2'; mode[5]='CALIBRADO_FIN'
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[isVariable(varName)
    (string) varName: nombre de la variable global
  comprueba si existe una variable global dada(varName) --]]
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[getDevice(nodeId)
    (number) nodeId: número del dispositivo a recuperar de la variable global
  recupera el dispositivo virtual desde la variable global --]]
function getDevice(nodeId)
  -- si  exite la variable global recuperar dispositivo
  local device = isVariable('dev'..nodeId)
  if device and device ~= 'NaN' and device ~= 0 and device ~= '' then
    device = json.decode(device)
    -- si esta iniciado devolver el dispositivo
    if device.nodeId then
      return device
     end
  end
  -- en cualquier otro caso error
  return false
end

--[[CALIBRADO
comenzamos el calibrado tomando la temperatura (t) ponemos la salida =
 (cycleTime - minTimeActiondurante) durante el tiempo indicado (tuneTime)
 cuando pasa el tiempo tomamos la temperatura para hayar el incremento de
 producido desde (t) a (th). [ih = th - t]
una vez se alcanzado el tiempo, poner salida = 0 comprobar la temperatura (th)
hasta que comience a bajar (thh) o hasta que pase tuneTime/2 para averiguar la
inercia térmica [iT = thh - th]

kP = cycleTime / (ih)
kI = cycleTime / (ih * 15)
KD = K.kI * 2
histeresis = thh - th
antiwindupReset = histeresis + (cycleTime / 2000)
]]

-- recuperar dispositivo
local termostatoVirtual = getDevice(thermostatId)
-- si no está calibrando previamente comenzar el calibrado
if termostatoVirtual.mode < 3 then
  fibaro:debug('Comienza calibrado Fase 1...')
  -- poner el PID en modo autoTune Fase 1 e indicar tiempo de calibrado
  local K = termostatoVirtual.K
  termostatoVirtual['K'].tuneTime = tuneTime; termostatoVirtual.mode = 3
  -- actualizar dispositivo
  fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
  -- inicializar temperatura inicial y temperatura tras tiempo de calibrado
  local t = termostatoVirtual.value; local th = t
  -- inicializar variable de instante de fin de calibrado
  tuneStamp = os.time() + tuneTime
  -- medir teperatura mientras transcurre el periodo de calibrado fase 1
  fibaro:debug('t = '..th)
  while os.time() <= tuneStamp do
    -- recuperar dispositivo
    termostatoVirtual = getDevice(thermostatId)
    th = termostatoVirtual.value
  end

  fibaro:debug('Comienza calibrado Fase 2...')
  -- poner el PID en modo autoTune Fase 2
  termostatoVirtual.mode = 4
  -- actualizar dispositivo
  fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
  -- inicializar temperatura de inercia
  local thh = th
  -- mientras la temperatura de la sonda no descienda tomar temperatura de
  -- inercia como máximo durante la mitad del tiempo de calibrado
  tuneStamp = os.time() + (tuneTime / 2)
  while termostatoVirtual.value >= th and os.time() <= tuneStamp do
    thh = termostatoVirtual.value
    -- recuperar dispositivo
    termostatoVirtual = getDevice(thermostatId)
  end
  fibaro:debug('thh = '..thh)

  K.histeresis = thh - th
  K.antiwindupReset = K.histeresis + ((3600/K.cyclesH) / 2000)
  fibaro:debug('histeresis='..K.histeresis..' antiwindupReset='
  ..K.antiwindupReset )
  local ih = thh - t
  -- evitar error division por 0
  if ih == 0 then ih = 1 end
  fibaro:debug('th = '..th)
  K.kP = math.floor((3600/K.cyclesH) / ih)
  K.kI = math.floor((3600/K.cyclesH) / (ih * 15))
  K.kD = K.kI * 2
  fibaro:debug('kP='..K.kP..' kI='..K.kI..' kD='..K.kD)

  -- guardar resultado
  termostatoVirtual.K = K
end

fibaro:debug('Finalizo calibrado')
-- indicar anulada o finalizado del calibrado
termostatoVirtual.mode = 5

-- actualizar dispositivo
fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
