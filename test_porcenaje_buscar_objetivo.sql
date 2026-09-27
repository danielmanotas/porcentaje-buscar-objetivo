WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON
DECLARE
    v_tasa NUMBER;
    PROCEDURE comprobar(p_condicion BOOLEAN, p_mensaje VARCHAR2) IS
    BEGIN
        IF p_condicion IS NULL OR NOT p_condicion THEN
            RAISE_APPLICATION_ERROR(-20000, p_mensaje);
        END IF;
    END;
BEGIN
    -- Un período: 3 * (1 + r) - 4 = 0; r = 1/3.
    v_tasa := calcular_buscar_objetivo(t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 4, 3)
    ), 1/3);
    comprobar(ABS(3 * (1 + v_tasa) - 4) <= 3E-18, 'Residuo fuera de tolerancia.');
    comprobar(v_tasa <> ROUND(v_tasa, 16), 'La tasa perdió precisión de salida.');

    -- Ordenación, exclusión de NULL, ABS y saldo procedente de un pago NULL.
    v_tasa := calcular_buscar_objetivo(t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(5, -110, NULL),
        t_buscar_objetivo_detalle(2, NULL, 100),
        t_buscar_objetivo_detalle(1, 0, NULL)
    ), NULL);
    comprobar(ABS(v_tasa - 0.1) <= 1E-18, 'Cambió el tratamiento de los registros.');

    -- Detectar seq = 2 duplicado, incluso cuando uno tiene pago NULL.
    BEGIN
        v_tasa := calcular_buscar_objetivo(t_buscar_objetivo_detalles(
            t_buscar_objetivo_detalle(1, 0, NULL),
            t_buscar_objetivo_detalle(2, 110, 100),
            t_buscar_objetivo_detalle(2, NULL, 100)
        ), NULL);
        RAISE_APPLICATION_ERROR(-20000, 'No se detectó seq = 2 duplicado.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -20015 THEN RAISE; END IF;
    END;
    DBMS_OUTPUT.PUT_LINE('Pruebas correctas.');
END;
/

-- Ejemplo de uso: saldo 100, pago 110, tasa esperada 0.1.
SET SERVEROUTPUT ON
DECLARE
    v_detalles t_buscar_objetivo_detalles := t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, 100)
    );
    v_tasa NUMBER;
BEGIN
    v_tasa := calcular_buscar_objetivo(v_detalles, NULL);
    DBMS_OUTPUT.PUT_LINE('Tasa por período: ' || TO_CHAR(v_tasa));
END;
/
