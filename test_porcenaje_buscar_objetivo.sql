WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON

/*
 * Pruebas: calcular_buscar_objetivo
 *
 * Propósito:
 *   Verifica errores de negocio, precisión de salida, reglas de pagos,
 *   respaldo por bisección y convergencia en secuencias de 60 y 120 períodos.
 *   Requiere ejecutar antes porcentaje_buscar_objetivo.sql.
 *
 * Resultado:
 *   Cada caso imprime OK. Una aserción fallida genera -20000 y detiene
 *   el script. Las pruebas no crean objetos ni modifican tablas.
 */
DECLARE
    v_casos      PLS_INTEGER := 0;
    v_tasa       NUMBER;
    v_detalles   t_buscar_objetivo_detalles;
    v_saldo      NUMBER;
    v_periodos   PLS_INTEGER;

    PROCEDURE comprobar(p_condicion BOOLEAN, p_mensaje VARCHAR2) IS
    BEGIN
        IF p_condicion IS NULL OR NOT p_condicion THEN
            RAISE_APPLICATION_ERROR(-20000, p_mensaje);
        END IF;
    END comprobar;

    PROCEDURE registrar(p_nombre VARCHAR2) IS
    BEGIN
        v_casos := v_casos + 1;
        DBMS_OUTPUT.PUT_LINE('OK: ' || p_nombre);
    END registrar;

    /*
     * Comprueba tasa y residuo con el mismo contrato de selección de pagos.
     * Retorna la tasa para las aserciones específicas de cada escenario.
     */
    FUNCTION verificar_tasa(
        p_nombre   VARCHAR2,
        p_detalles t_buscar_objetivo_detalles,
        p_semilla  NUMBER,
        p_esperada NUMBER
    ) RETURN NUMBER IS
        v_resultado NUMBER;
        v_inicial   NUMBER;
        v_residuo   NUMBER;
        v_posicion  PLS_INTEGER := 0;
    BEGIN
        v_resultado := calcular_buscar_objetivo(p_detalles, p_semilla);
        comprobar(v_resultado > -0.99999999 AND v_resultado <= 100,
                  p_nombre || ': tasa fuera del dominio.');
        comprobar(ABS(v_resultado - p_esperada) <= 1E-18,
                  p_nombre || ': tasa distinta de la esperada.');
        SELECT saldo_inicial INTO v_inicial
        FROM TABLE(p_detalles) WHERE seq = 2;
        v_residuo := v_inicial;
        FOR pago IN (
            SELECT valor_pagos FROM TABLE(p_detalles)
            WHERE valor_pagos IS NOT NULL ORDER BY seq
        ) LOOP
            v_posicion := v_posicion + 1;
            IF v_posicion > 1 THEN
                v_residuo := v_residuo * (1 + v_resultado) - ABS(pago.valor_pagos);
            END IF;
        END LOOP;
        comprobar(ABS(v_residuo) <= ABS(v_inicial) * 1E-18,
                  p_nombre || ': residuo fuera de tolerancia.');
        DBMS_OUTPUT.PUT_LINE('  ' || p_nombre || ': tasa=' || TO_CHAR(v_resultado, 'TM9')
            || ', residuo=' || TO_CHAR(v_residuo, 'TM9'));
        RETURN v_resultado;
    END verificar_tasa;

    /*
     * Captura únicamente la llamada bajo prueba y comprueba su SQLCODE.
     * Una llamada sin excepción también se considera un fallo del caso.
     */
    PROCEDURE esperar_error(
        p_nombre   VARCHAR2,
        p_detalles t_buscar_objetivo_detalles,
        p_codigo   PLS_INTEGER
    ) IS
        v_codigo PLS_INTEGER := 0;
        v_valor  NUMBER;
    BEGIN
        BEGIN
            v_valor := calcular_buscar_objetivo(p_detalles, NULL);
        EXCEPTION
            WHEN OTHERS THEN v_codigo := SQLCODE;
        END;
        comprobar(v_codigo = p_codigo,
            p_nombre || ': esperado ' || p_codigo || ', recibido ' || v_codigo);
        registrar(p_nombre);
    END esperar_error;
BEGIN
    v_tasa := verificar_tasa('Tasa sin redondeo', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 4, 3)
    ), 1/3, 1/3);
    comprobar(v_tasa <> ROUND(v_tasa, 16), 'La tasa perdió precisión de salida.');
    registrar('Tasa sin redondeo');

    v_tasa := verificar_tasa('Orden, NULL y ABS', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(5, -110, NULL),
        t_buscar_objetivo_detalle(2, NULL, 100),
        t_buscar_objetivo_detalle(1, 0, NULL)
    ), NULL, 0.1);
    registrar('Orden, NULL y ABS');

    esperar_error('Menos de dos pagos no nulos', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, NULL, NULL),
        t_buscar_objetivo_detalle(2, 110, 100)
    ), -20011);
    esperar_error('Falta seq = 2', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(3, 110, 100)
    ), -20012);
    esperar_error('Saldo NULL', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, NULL)
    ), -20012);
    esperar_error('Saldo cero', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, 0)
    ), -20012);
    esperar_error('Saldo negativo', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, -100)
    ), -20012);

    -- 1 * (1 + r) - 102 = 0 exige r = 101, fuera del dominio.
    esperar_error('Raiz superior a 100', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 102, 1)
    ), -20014);
    -- 100 * (1 + r) = 0 exige r = -1, excluido del dominio.
    esperar_error('Todos los pagos aplicados son cero', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 0, 100)
    ), -20014);
    esperar_error('Seq repetido entre pagos', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, 100),
        t_buscar_objetivo_detalle(3, 10, NULL),
        t_buscar_objetivo_detalle(3, 20, NULL)
    ), -20015);
    esperar_error('Seq = 2 duplicado con pago NULL', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, 100),
        t_buscar_objetivo_detalle(2, NULL, 100)
    ), -20015);

    -- Solo un pago retenido y dos registros seq = 2: prima -20011.
    esperar_error('Cantidad antes de duplicidad', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(2, 110, 100),
        t_buscar_objetivo_detalle(2, NULL, 100)
    ), -20011);
    -- Dos pagos repetidos, sin seq = 2: prima -20015.
    esperar_error('Duplicidad antes de ausencia de saldo', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(1, 110, NULL)
    ), -20015);

    -- 100 * (1 + r)^2 - 121 = 0: el cero genera el primer período.
    v_tasa := verificar_tasa('Pago cero intermedio', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 0, 100),
        t_buscar_objetivo_detalle(3, 121, NULL)
    ), 0.02, 0.1);
    registrar('Pago cero intermedio');

    v_tasa := verificar_tasa('Tasa negativa', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 80, 100)
    ), NULL, -0.2);
    comprobar(v_tasa < 0, 'Se alteró el signo de la tasa.');
    registrar('Tasa negativa');

    -- F(r)=100*x*x-40*x-5, x=1+r. En r=-0.8: F=-9, F'=0.
    -- Newton debe salir sin converger; bisección acepta la raíz r=-0.5.
    comprobar(200 * (1 - 0.8) - 40 = 0, 'Precondición: derivada cero.');
    comprobar(100 * (1 - 0.8) * (1 - 0.8) - 40 * (1 - 0.8) - 5 = -9,
              'Precondición: residuo no nulo.');
    v_tasa := verificar_tasa('Respaldo por biseccion', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 40, 100),
        t_buscar_objetivo_detalle(3, 5, NULL)
    ), -0.8, -0.5);
    registrar('Respaldo por biseccion');

    -- F(r)=100*x*x-20*x-3. En r=-0.9: F=-4, F'=0.
    -- F(-0.5)=12 y F(2)=837: se debe expandir el extremo inferior.
    -- La raíz r=-0.7 no es un extremo; requiere iteraciones de bisección.
    comprobar(200 * (1 - 0.9) - 20 = 0, 'Precondición: derivada cero.');
    comprobar(100 * (1 - 0.9) * (1 - 0.9) - 20 * (1 - 0.9) - 3 = -4,
              'Precondición: residuo no nulo.');
    comprobar(100 * 0.5 * 0.5 - 20 * 0.5 - 3 > 0
              AND 100 * 3 * 3 - 20 * 3 - 3 > 0,
              'Precondición: ambos extremos positivos.');
    v_tasa := verificar_tasa('Biseccion bajo -0.50', t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 20, 100),
        t_buscar_objetivo_detalle(3, 3, NULL)
    ), -0.9, -0.7);
    registrar('Biseccion bajo -0.50');

    -- Construir el saldo por descuento inverso de pagos de 1000 al 1 %.
    -- No se usa POWER ni se proporciona la raíz como semilla.
    FOR escenario IN 1 .. 2 LOOP
        v_periodos := escenario * 60;
        v_saldo := 0;
        FOR i IN 1 .. v_periodos LOOP
            v_saldo := (v_saldo + 1000) / 1.01;
        END LOOP;
        v_detalles := t_buscar_objetivo_detalles();
        v_detalles.EXTEND(v_periodos + 1);
        v_detalles(1) := t_buscar_objetivo_detalle(1, 0, NULL);
        FOR i IN 2 .. v_periodos + 1 LOOP
            v_detalles(i) := t_buscar_objetivo_detalle(i, 1000, NULL);
        END LOOP;
        v_detalles(2).saldo_inicial := v_saldo;
        v_tasa := verificar_tasa('Secuencia de ' || v_periodos || ' periodos',
                                v_detalles, 0.02, 0.01);
        registrar('Secuencia de ' || v_periodos || ' periodos');
    END LOOP;

    -- Verificar la API opcional y el nombre público de la semilla.
    v_detalles := t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1, 0, NULL),
        t_buscar_objetivo_detalle(2, 110, 100)
    );
    v_tasa := calcular_buscar_objetivo(p_detalles => v_detalles);
    comprobar(v_tasa = 0.1, 'El parámetro omitido debe utilizar 0.1.');
    registrar('Semilla omitida');

    v_tasa := calcular_buscar_objetivo(
        p_detalles => v_detalles, p_semilla_inicial => 0.05
    );
    comprobar(ABS(v_tasa - 0.1) <= 1E-18, 'Falló la semilla con nombre.');
    comprobar(ABS(100 * (1 + v_tasa) - 110) <= 100 * 1E-18,
              'Residuo fuera de tolerancia con semilla explícita.');
    registrar('Semilla explícita con nombre');

    v_tasa := verificar_tasa('Semilla NULL', v_detalles, NULL, 0.1);
    registrar('Semilla NULL');
    v_tasa := verificar_tasa('Semilla en límite inferior excluido',
                            v_detalles, -0.99999999, 0.1);
    registrar('Semilla en límite inferior excluido');
    v_tasa := verificar_tasa('Semilla superior al dominio', v_detalles, 101, 0.1);
    registrar('Semilla superior al dominio');

    DBMS_OUTPUT.PUT_LINE('Pruebas correctas: ' || v_casos || ' casos.');
END;
/
