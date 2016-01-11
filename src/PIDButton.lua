--[[ TermostatoVirtual
	Dispositivo virtual
	PIDButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local kP = 200 -- Proporcional
local kI = 10 -- Integral
local kD = 20 -- Derivativo
local Intervalo = 10 -- intervalo de medición en segundos
-- tiempo por ciclo en minutos: 10 minutos (6 ciclos/h) etc...
local TiempoCiclo = .25
local Histeresis = 0.2 -- histeresis en grados
-- Identificacion panel de calefaccion a seguir
local HeatingPanelID = idPaneles["INTERIOR"]
-- Indentificacion del ID del VD del termostato
local TermostatoVDID = idVD["TERMOSTATO"]
-- Identificar del ID que activa el actuador de encendido de la calefaccion
local ActuadorID = id["TERMOSTATO"]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

--[[----------------------------------------------------------------------------
isVariable(varName)
	comprueba si existe una variable global dada(varName)
--]]
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[----------------------------------------------------------------------------
getDevice(nodeId)
	recupera el dispositivo virtual desde la variable global
  (number)
--]]
function getDevice(nodeId)
  -- si  exite la variable global recuperar dispositivo
  local device = isVariable('dev'..nodeId)
  if device then
    return json.decode(device)
  end
end

--[[Inicializar()
  Inicializa variables --]]
function Inicializar()
	--if TiempoCiclo < 5 then TiempoCiclo = 5 end -- ciclo mínimo es de 5 min
	local FactorEscala = TiempoCiclo / 5
	local Actual = 0 -- Actual temperatura
	local Err = 0 -- Error: diferencia entre consigna y valor actual
	local UltimoErr = 0 -- Error en la iteracion anterior
	local SumErr = 0 -- Suma error calculado
	local Actuador = 0 -- Actuador on/off
	local Salida = 0 -- Salida: Tiempo a conectar la calefaccion
	return TiempoCiclo,FactorEscala,Actual,Err,UltimoErr,SumErr,Actuador,Salida;
end

--[[
CalculoError(Actual, Consigna)
	Calculo del error diferencia entre temperatura Actual y Consigna
------------------------------------------------------------------------------]]
function CalculoError(Actual, Consigna)
	return tonumber(Consigna) - tonumber(Actual)
end

--[[
CalculoProporcional(Err,kP)
	Calculo del termino proporcional
------------------------------------------------------------------------------]]
function CalculoProporcional(Err,kP)
	P = Err*kP -- Termino proporcional
	return P
end

--[[
CalculoIntegral(SumErr, kI)
	Calculo del termino integral
------------------------------------------------------------------------------]]
function CalculoIntegral(SumErr, kI)
	I = SumErr*kI -- Termino integral
	return I
end

--[[
CalculoDerivativo(Err,UltimoErr,kD)
	Calculo del termino derivativo
------------------------------------------------------------------------------]]
function CalculoDerivativo(Err,UltimoErr,kD)
	D = (Err - UltimoErr)*kD -- Termino derivativo
	return D
end

--[[
AntiWindUp(SumErr, Err, Histeresis)
------------------------------------------------------------------------------]]
function AntiWindUp(SumErr, Err, Histeresis)
	-- si el error está fuera del rango de histeresis, acumular error
	if math.abs(Err) < Histeresis then
		return SumErr + Err
	end
	-- si está dentro del rango de histeresis, anti WindUp
	return 0
end

--[[
putCalefaccion(Salida,ActuadorID,FactorEsc
------------------------------------------------------------------------------]]
function putCalefaccion(Salida, ActuadorID, FactorEscala)
	if (Salida > 0) -- Tiempo de calentamiento debe ser positivo para encender
	then
		if Salida > 300 then Salida = 300 end
		Salida = Salida*FactorEscala;
		fibaro:debug("Activando calefacción durante "..Salida.." segundos."); -- Tiempo de activación calefaccion
	else
		fibaro:debug("No requiere calentamiento");
	end

	--fibaro:setGlobal("BoilerOnTime", heatingTime)
	--fibaro:startScene(53) -- start boiler activator
	return 0
end

--[[----------------------- COMIENZA LA EJECUCION ----------------------------]]

-- Control de escenas funcionando
if (fibaro:countScenes()>1) then
	fibaro:debug('Escena arrancada')
	fibaro:abort()
else
	fibaro:debug("Escena única")
end

------------------------ Calculos -----------------------------
-- Inicializar Variables
local TiempoCiclo,FactorEscala,Actual,Err,UltimoErr,SumErr,Actuador,Salida =
 Inicializar()

 -- recuperar dispositivo
 local termostatoVirtual = getDevice(_selfId)

	-- leer temperatura del sensor
  Actual = termostatoVirtual.value
  -- leer temperatura de consigna
	Consigna = termostatoVirtual.targetLevel
	Err = CalculoError(Actual, Consigna)
	fibaro:debug('SumErr: '..SumErr.." Err: "..Err..' Histeresis: '..Histeresis)
	SumErr = AntiWindUp(SumErr, Err, Histeresis)
	P = CalculoProporcional(Err, kP)
	fibaro:debug("P="..P)
	I = CalculoIntegral(SumErr, kI)
	fibaro:debug("I="..I)
	D = CalculoDerivativo(Err, UltimoErr, kD)
	fibaro:debug("D="..D)
	Salida = P + I + D -- Accion total = P+I+D
	Integral = 0 --reset integral WindUp
	UltimoErr = Err -- Actualizo ultimo error
	putCalefaccion(Salida, ActuadorID, FactorEscala) -- Activa calefaccion si es preciso
	Salida = 0 -- reset de la salida
	fibaro:sleep(TiempoCiclo*60*1000) -- Esperamos al siguiente ciclo
