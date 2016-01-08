--[[
%% properties
%% autostart
%% globals
--]]

-- DEFINICIONES DE DISPOSITIVOS
local id = {
--Cocina
NFC = 76, ESTOR = 49, TECLA = 17, PERSIANA = 7,
--Entrada
MOVIMIENTO = 50, CAM_ENTRADA = 85, TEMPERATURA2 = 79, LUZ = 287, SIRENA = 35, CORRIENTETABLET = 71, TEMPERATURA = 51, LUMINOSIDAD = 52, PUERTA = 77, ENERGIA = 214,
--Salon
TEMPERATURA_SALON = 54, MOVIMIENTO_SALON = 53, LUMINOSIDAD_SALON = 55, TECLADERECHA = 34, TECLAIZQUIERDA = 32, ESTOR_DERECHA = 31, PERSIANA_IZQUIERDA = 97, PERSIANA_CENTRAL = 22, PERSIANA_DERECHA = 21, TECLACENTRO = 33, ESTOR_IZQUIERDA = 24, ESTOR_CENTRAL = 27, MEDIACENTER = 30,
--Noa
VENTANA = 80, TEMPERATURA_NOA = 82, VIBRACION = 46, ARMARIO = 14, PERSIANA_NOA = 13, TECLA_NOA = 20, LUZ_NOA=187,
--Nahia
PERSIANA_NAHIA = 15, TECLA_NAHIA = 19, VENTANA_NAHIA = 39, VIBRACION_NAHIA = 47, TEMPERATURA_NAHIA = 41, LUZ_NAHIA = 188,
--Matrimonio
VIBRACION_MATRIMONIO = 45, VENTANA_MATRIMONIO = 42, TECLA_MATRIMONIO = 18, PERSIANA_MATRIMONIO = 12, TEMPERATURA_MATRIMONIO = 44, LUZ_MATRIMONIO=190,
--General
GENERAR_ID = 95, PERSIANAS_SALON = 25, GLOBAL_PERSIANAS = 26, ESTORES_SALON = 28,
--Terraza
CAM_TERRAZA = 84,
--Seguridad
TECLADO_ALARMA = 61, MAXDISPOSITIVOS = 93, PUERTASVENTANASABIERT = 60, SURVEILLANCE_STATION = 75,
--Horarias
CLOCK_SYNC = 64,
--Informativa
NAS_DS213J = 72, LOGGER = 62, EN_CASA = 68, PUSHOVER = 94,
--TTS
TEXTTOSPECH = 63,
--Baños
VENTILACION = 271, VENTPEQUENO = 279, VENTGRANDE = 275,
--Climatización
TEMPERATURACLIMA=404, TERMOSTATO = 298,
}

local idscenas = {
ARMADO_TOTAL = 8, ARMADO_PARCIAL = 9, DESARMADO = 10, PTZ=197
}

local idVD = {
GLOBALPERSIANAS = 26, PERSIANASSALON = 25, ESTORESSALON = 28, TERMOSTATO =581,
}

local idPaneles = { INTERIOR = 271,}


-- uso :
-- fibaro:getValue(id["TEXTTOSPECH"], "value")
-- GEA.add(id["TEXTTOSPECH"], 30, "")

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

--[[
getConsigna()
	Devuelve el valor de consigna del VD del termostato
------------------------------------------------------------------------------]]
function getConsigna()
	local tempConsigna
	if (fibaro:getValue(idVD["TERMOSTATO"],"ui.Modo.value")=="Manual") then
		fibaro:debug("Termostato Modo Manual")
		tempConsigna = fibaro:getValue(idVD["TERMOSTATO"], "ui.SP.value")
	elseif (fibaro:getValue(idVD["TERMOSTATO"],"ui.Modo.value")=="Auto") then
		fibaro:debug("Termostato Modo AUTO")
		tempConsigna = fibaro:getValue(idVD["TERMOSTATO"], "ui.SPAUTO.value")
	elseif (fibaro:getValue(idVD["TERMOSTATO"],"ui.Modo.value")=="Off") then
		fibaro:debug("Termostato Modo OFF")
		tempConsigna = fibaro:getValue(idVD["TERMOSTATO"], "ui.SPOFF.value")
	else -- ERROR
		tempConsigna = false
	end
	-- esperar hasta obtener una temperatura de consigna
	while not tempConsigna or tempConsigna == '' or tempConsigna == 0 do
		fibaro:debug('Esperando temperatura de consigna')
		fibaro:sleep(TiempoCiclo*60*1000) -- Esperamos al siguiente ciclo
		return getConsigna()
	end
	return tempConsigna
end

--[[
Inicializar()
	Inicializa variables
------------------------------------------------------------------------------]]
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
getActual()
	devolver temperatura actual
------------------------------------------------------------------------------]]
function getActual()
	return fibaro:getValue(id["TEMPERATURACLIMA"], "value")
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

--[[-------------------------- BUCLE PRINCIPAL -------------------------------]]
fibaro:debug("Iniciando bucle...")
while true do
	Actual = getActual() -- Leo temperatura del sensor
	Consigna = getConsigna() -- Leo temperatura de consigna
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
end
