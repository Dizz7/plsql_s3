-- USUARIO EA1_3_MDY_FOL

/* Se modificó la contraseña del usuario de EA1_3-CreaUsuario.sql por 
   requerimiento de seguridad de Oracle SQL Developer (contraseña 'duoc')

   La línea alterada fue esta: 

   CREATE USER EA1_3_MDY_FOL IDENTIFIED BY "H0l4.O_r4cL3!"
	
*/



-- FUNCIÓN ALMACENADA 1

/* Función almacenada que retorna la cantidad total
   de atenciones registradas de una especialidad
   dado un periodo de tiempo (MM-YYYY) y 
   un ID de especialidad. */
    


CREATE OR REPLACE FUNCTION fn_cant_aten_esp (
    p_id_especialidad NUMBER,
    p_periodo VARCHAR2)
    RETURN NUMBER

IS
    cant_atenciones_esp NUMBER;
    v_inicio_mes DATE;
    v_fin_mes DATE;

BEGIN
    -- Definir el inicio y fin del mes según el periodo
    v_inicio_mes := TO_DATE('01-' || p_periodo, 'DD-MM-YYYY');
    v_fin_mes := LAST_DAY(v_inicio_mes);

    -- Obtener el número de atenciones de la especialidad en el periodo
    SELECT 
        NVL(COUNT(ate_id), 0)
    INTO cant_atenciones_esp
    FROM atencion
    WHERE esp_id = p_id_especialidad
    AND fecha_atencion BETWEEN v_inicio_mes AND v_fin_mes;

    -- Retornar la cantidad total de atenciones de la especialidad en el periodo
    RETURN cant_atenciones_esp;

END fn_cant_aten_esp;
/



-- PROBAR FUNCIÓN fn_cant_aten_esp

DECLARE
v_cantidad number;

BEGIN
    v_cantidad := fn_cant_aten_esp(300,'06-2024');
    DBMS_OUTPUT.PUT_LINE(v_cantidad);

END;
/





-- FUNCIÓN ALMACENADA 2

/* Función almacenada que retorna el costo total
   de atenciones registradas de una especialidad
   dado un periodo de tiempo (MM-YYYY) y 
   un ID de especialidad. */


CREATE OR REPLACE FUNCTION fn_costo_aten_esp (
    p_id_especialidad NUMBER,
    p_periodo VARCHAR2)
    RETURN NUMBER

IS
    costo_atenciones_esp NUMBER;
    v_inicio_mes DATE;
    v_fin_mes DATE;

BEGIN
    -- Definir el inicio y fin del mes según el periodo
    v_inicio_mes := TO_DATE('01-' || p_periodo, 'DD-MM-YYYY');
    v_fin_mes := LAST_DAY(v_inicio_mes);

    -- Obtener el número de atenciones de la especialidad en el periodo
    SELECT 
        NVL(SUM(costo), 0)
    INTO costo_atenciones_esp
    FROM atencion
    WHERE esp_id = p_id_especialidad
    AND fecha_atencion BETWEEN v_inicio_mes AND v_fin_mes;

    -- Retornar la cantidad total de atenciones de la especialidad en el perido
    RETURN costo_atenciones_esp;

END fn_costo_aten_esp;
/



-- PROBAR FUNCIÓN fn_costo_aten_esp

DECLARE
v_costo number;

BEGIN
    v_costo := fn_costo_aten_esp(300,'06-2024');
    DBMS_OUTPUT.PUT_LINE(v_costo);

END;
/











-- PROCEDIMIENTO ALMACENADO (PRINCIPAL)

/* Procedimiento almacenado para generar
   ambos informes solicitados ingresando
   un periodo MM-YYYY. */


CREATE OR REPLACE PROCEDURE sp_generar_informes (
    p_periodo VARCHAR2) 

IS

    -- Cursor explícito para obtener las especialidades
    CURSOR cr_especialidades IS 
        SELECT 
            e.esp_id AS id_especialidad,
            e.nombre AS nombre_especialidad
        FROM especialidad e;

    -- Variables para almacenar datos del cursor
    v_id_esp            ESPECIALIDAD.esp_id%TYPE;
    v_nombre_esp        ESPECIALIDAD.nombre%TYPE;

    -- Variables para cálculos
    v_total_atenciones NUMBER;
    v_costo_atenciones NUMBER;
    v_total_medicos NUMBER;
    v_categoria VARCHAR2(1);
    v_pago_a_tiempo VARCHAR2(2);
    v_existente NUMBER;

    -- Cursor explícito para obtener datos de pagos
    CURSOR cr_pagos IS  
        SELECT pa.monto_atencion, pa.fecha_pago, pa.fecha_venc_pago, a.fecha_atencion, pa.monto_a_cancelar
        FROM pago_atencion pa  
        JOIN atencion a ON pa.ate_id = a.ate_id  
        WHERE a.esp_id = v_id_esp
        AND TO_CHAR(a.fecha_atencion,'MM-YYYY') = p_periodo ;

    -- Variable para almacenar una fila completa de pago_atencion  
    v_pagos cr_pagos%ROWTYPE;  

BEGIN
    -- Borrado de tablas DETALLE_ESPECIALIDAD y RESUMEN_ESPECIALIDAD
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ESPECIALIDAD';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_ESPECIALIDAD';

    -- Abrir el cursor explícito de especialidades
    OPEN cr_especialidades;
    
    LOOP 
        -- Obtener la siguiente fila del cursor
        FETCH cr_especialidades INTO v_id_esp, v_nombre_esp;
        EXIT WHEN cr_especialidades%NOTFOUND;

        -- Obtener el total de médicos de la especialidad con cursor implícito
        SELECT 
            NVL(COUNT(DISTINCT med_run), 0) 
        INTO v_total_medicos
        FROM especialidad_medico
        WHERE esp_id = v_id_esp;

        -- Obtener la cantidad total de atenciones de la especialidad en el período en proceso
        v_total_atenciones := fn_cant_aten_esp(v_id_esp, p_periodo);

        -- Si no hay atenciones, asignar 0 como costo
        IF v_total_atenciones = 0 THEN
            v_costo_atenciones := 0;
        ELSE
            -- Obtener el costo total de las atenciones de la especialidad en el período en proceso
            v_costo_atenciones := fn_costo_aten_esp(v_id_esp, p_periodo);
        END IF;

        -- Categorías de atenciones según costo total de atenciones (regla de negocio)
        v_categoria := (CASE 
                           WHEN v_costo_atenciones BETWEEN 1 AND 19999 THEN 'A'
                           WHEN v_costo_atenciones BETWEEN 20000 AND 50000 THEN 'B'
                           WHEN v_costo_atenciones BETWEEN 50001 AND 100000 THEN 'C'
                           WHEN v_costo_atenciones > 100000 THEN 'D'
                           ELSE '-'
                        END); 

        -- Verificar si ya existe un registro en RESUMEN_ESPECIALIDAD
        SELECT COUNT(*)
        INTO v_existente
        FROM RESUMEN_ESPECIALIDAD
        WHERE esp_id = v_id_esp AND periodo = p_periodo;

        IF v_existente > 0 THEN
            -- Si el registro existe, realizar un UPDATE
            UPDATE RESUMEN_ESPECIALIDAD
            SET total_medicos = v_total_medicos,
                total_atenciones_periodo = v_total_atenciones,
                costo_total_periodo = v_costo_atenciones,
                categoria = v_categoria
            WHERE esp_id = v_id_esp AND periodo = p_periodo;
        ELSE
            -- Si el registro no existe, realizar un INSERT
            INSERT INTO RESUMEN_ESPECIALIDAD 
                (esp_id, nombre_especialidad, periodo, total_medicos, total_atenciones_periodo, costo_total_periodo, categoria)
            VALUES 
                (v_id_esp, v_nombre_esp, p_periodo, v_total_medicos, v_total_atenciones, v_costo_atenciones, v_categoria);
        END IF;

        -- Abrir cursor explícito de pagos
        OPEN cr_pagos;  
            
        LOOP  
            -- Obtener una fila de pagos  
            FETCH cr_pagos INTO v_pagos;  
            EXIT WHEN cr_pagos%NOTFOUND;  

            -- Corroborar si el pago fue a tiempo
            v_pago_a_tiempo := (CASE 
                                    WHEN v_pagos.fecha_pago <= v_pagos.fecha_venc_pago THEN 'SI'
                                    ELSE 'NO'
                                END); 

            -- Insertar en tabla DETALLE_ESPECIALIDAD
            INSERT INTO DETALLE_ESPECIALIDAD 
                (correlativo, esp_id, fecha_atencion, costo_atencion, monto_pago, fecha_pago, pago_a_tiempo)
            VALUES 
                (SEQ_DETALLE.NEXTVAL, v_id_esp, v_pagos.fecha_atencion, v_pagos.monto_atencion, v_pagos.monto_a_cancelar, v_pagos.fecha_pago, v_pago_a_tiempo);

        COMMIT;
        -- Cerrar loop cursor pagos
        END LOOP;
        -- Cerrar cursor de pagos  
        CLOSE cr_pagos;  

    -- Cerrar loop cursor especialidades
    END LOOP;
    -- Cerrar cursor de especialidades
    CLOSE cr_especialidades;
END sp_generar_informes;
/  






/* Valores para realizar las pruebas 
   del ejercicio */


-- Prueba de Procedimiento Almacenado (principal)
DECLARE
BEGIN
   sp_generar_informes('06-2024');
END;
/




-- Revisar Tablas

-- Tabla DETALLE_ESPECIALIDAD

SELECT
    correlativo, 
    esp_id, 
    TO_CHAR(fecha_atencion, 'DD-MON-YY') AS fecha_atencion,
    costo_atencion, 
    monto_pago, 
    TO_CHAR(fecha_pago, 'DD-MON-YY') AS fecha_pago, 
    pago_a_tiempo
FROM DETALLE_ESPECIALIDAD ORDER BY correlativo;



-- Tabla RESUMEN_ESPECIALIDAD

SELECT * FROM RESUMEN_ESPECIALIDAD ORDER BY esp_id;







