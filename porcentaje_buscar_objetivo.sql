WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

/*
 * Tipo: t_buscar_objetivo_detalle
 *
 * Propósito:
 *   Contiene la información de un registro para calcular la tasa objetivo.
 *
 * Atributos:
 *   seq           : Secuencia utilizada para ordenar los pagos.
 *   valor_pagos   : Importe del pago; NULL excluye el registro de los pagos.
 *   saldo_inicial : Saldo de partida; se utiliza en el único registro seq = 2.
 */
CREATE OR REPLACE TYPE t_buscar_objetivo_detalle AS OBJECT (
    seq           NUMBER,
    valor_pagos   NUMBER,
    saldo_inicial NUMBER
);
/

/*
 * Tipo: t_buscar_objetivo_detalles
 *
 * Propósito:
 *   Agrupa los registros de entrada, incluidos los pagos NULL necesarios
 *   para validar la existencia y unicidad del registro con seq = 2.
 */
CREATE OR REPLACE TYPE t_buscar_objetivo_detalles
    AS TABLE OF t_buscar_objetivo_detalle;
/

SHOW ERRORS TYPE t_buscar_objetivo_detalle
SHOW ERRORS TYPE t_buscar_objetivo_detalles

  /*
  * Función: calcular_buscar_objetivo
  *
  * Propósito:
  *   Calcula la tasa por período que permite amortizar un saldo inicial
  *   mediante una secuencia de pagos hasta obtener un saldo final cero.
  *
  * Parámetros:
  *   p_detalles : Colección t_buscar_objetivo_detalles con seq, valor_pagos y
  *                saldo_inicial de los registros que se desean procesar.
  *   p_tie      : TIE previamente calculada, en tanto por uno; admite NULL.
  *
  * Datos y validaciones:
  *   Se excluyen los registros con valor_pagos NULL y se ordenan por seq
  *   ascendente. Se requieren al menos dos registros. El saldo inicial se toma
  *   directamente de saldo_inicial del unico registro con seq = 2,
  *   sin redondearlo ni aplicar ABS. Debe ser no nulo y mayor que cero.
  *   Cada posición desde la segunda de la lista filtrada representa un
  *   período y su pago se toma en valor absoluto.
  *   La recurrencia usa la secuencia de pagos, no diferencias entre fechas.
  *
  * Cálculo:
  *   saldo_1 = saldo_inicial del registro con seq = 2
  *   saldo_i = saldo_(i-1) * (1 + r) - ABS(pago_i), para i = 2 .. n.
  *   Se busca la tasa r que satisface saldo_n = 0, mediante Newton-Raphson
  *   con reducción del paso y bisección con expansión acotada como respaldo.
  *
  * Semilla:
  *   Se utiliza primero p_tie. Se utiliza 0.1 cuando esa TIE es NULL o está
  *   fuera del dominio admitido. El llamador obtiene la TIE y, si su cálculo
  *   genera -20004, -20005, -20006, -20007 o -20008, debe pasar NULL para
  *   conservar el respaldo original. Los demás errores se gestionan fuera
  *   de esta función, antes de invocarla.
  *
  * Consistencia de lectura:
  *   Los pagos y el saldo inicial se obtienen de p_detalles; la semilla,
  *   de p_tie. El llamador debe preparar los parámetros con el contexto
  *   transaccional apropiado si deben proceder de la misma instantanea.
  *
  * Parámetros numéricos:
  *   Dominio admitido para la raíz interna: -0.99999999 < r <= 100.
  *   Máximo: 100 iteraciones por método.
  *   Tolerancia de saldo: ABS(saldo_inicial de seq = 2) * 1E-18.
  *   Tolerancia absoluta de tasa: 1E-18.
  *   Newton acepta un residuo cero o exige simultáneamente la tolerancia de
  *   saldo y ABS(saldo_final / derivada) <= 1E-18. Bisección comprueba el
  *   residuo y la amplitud del intervalo. La aritmética interna utiliza NUMBER.
  *
  * Retorno:
  *   NUMBER: tasa por período en tanto por uno, sin redondeo de salida.
  *   La raíz se valida antes de retornarla. Los períodos de los pagos determinan
  *   la periodicidad de la tasa; la TIE mensual solo constituye la semilla.
  *
  * Errores mediante RAISE_APPLICATION_ERROR:
  *   -20011: Menos de dos pagos con valor no nulo.
  *   -20012: Falta seq = 2 o su saldo inicial es NULL, cero o negativo.
  *   -20014: No se obtiene una solución admitida por los límites y tolerancias.
  *   -20015: seq repetido en los pagos o mas de un registro con seq = 2.
  *   -20999: Error inesperado; incluye SQLERRM y la traza de ejecución.
  *
  *   Alcances y limitaciones:
  *   La posición de la colección no es el valor de seq. Se omite siempre
  *   la primera posición filtrada, aunque no corresponda a seq = 1.
  *   No exige secuencias consecutivas ni una segunda posición con seq = 2.
  *   La consulta del saldo incluye elementos cuyo valor_pagos es NULL.
  *   Un pago NULL no genera período; un pago cero retenido sí lo genera.
  *   Con n filas se aplican n - 1 períodos. No redondea saldos intermedios
  *   ni exige su positividad. ABS elimina el signo de los pagos aplicados.
  *   La ecuación equivale a S = SUM(A_k / (1 + r)^k), k = 1 .. n - 1,
  *   donde S es el saldo inicial y A_k = ABS(pago en posición k + 1).
  *   La tasa solo es mensual si cada posición aplicada representa un mes.
  *   Se retorna la misma raíz que supera la prueba del residuo.
  */
CREATE OR REPLACE FUNCTION calcular_buscar_objetivo (
      p_detalles IN t_buscar_objetivo_detalles,
      p_tie      IN NUMBER
  ) RETURN NUMBER IS
    -- Pagos ordenados por seq: se omite la primera posición de la lista filtrada.
    -- El saldo de partida procede de saldo_inicial donde seq = 2.
    TYPE t_pagos IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_repeticiones IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;

    v_pagos     t_pagos;
    v_repeticiones t_repeticiones;
    v_n         PLS_INTEGER;
    v_saldo_ini NUMBER;
    v_cant_seq2 PLS_INTEGER;
    v_x         NUMBER;
    v_ok        BOOLEAN := FALSE;
    -- Identifica las excepciones de negocio emitidas por esta función.
    v_error_negocio BOOLEAN := FALSE;
    e_pf_overflow EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_pf_overflow, -1426);
    v_metodo       VARCHAR2(20) := 'VALIDACION';
    v_iteracion    PLS_INTEGER := 0;

    -- Tolerancias del residuo y de la tasa, y límites de búsqueda.
    c_tol_rel   CONSTANT NUMBER      := 1E-18;
    c_tol_rate  CONSTANT NUMBER      := 1E-18;
    c_max_iter  CONSTANT PLS_INTEGER := 100;
    c_min_rate  CONSTANT NUMBER      := -0.99999999;
    c_max_rate  CONSTANT NUMBER      := 100.0;

    /*
     * Evalúa el saldo final y su derivada para p_rate en una sola pasada.
     * La derivada se actualiza antes del saldo para utilizar el saldo del
     * período anterior: derivada_i = derivada_(i-1) * (1 + r) + saldo_(i-1).
     * p_saldo_final y p_derivada contienen los resultados del último período.
     *
     *   Entrada: p_rate, tasa por período en tanto por uno.
     *   Estado inicial: saldo = v_saldo_ini y derivada = 0.
     *   Recorre posiciones 2 .. v_n, no valores de seq 2 .. v_n.
     *   Cada paso capitaliza primero y descuenta después el pago absoluto.
     *   No aplica redondeo intermedio.
     */
    PROCEDURE f_evaluar(
        p_rate        IN  NUMBER,
        p_saldo_final OUT NUMBER,
        p_derivada    OUT NUMBER
    ) IS
      v_factor NUMBER := 1.0 + p_rate;
      v_acc    NUMBER := v_saldo_ini;
      v_dacc   NUMBER := 0.0;
    BEGIN
      FOR i IN 2 .. v_n LOOP
        v_dacc := v_dacc * v_factor + v_acc;
        v_acc  := v_acc * v_factor
                  - ABS(v_pagos(i));
      END LOOP;

      p_saldo_final := v_acc;
      p_derivada    := v_dacc;
    END f_evaluar;

    /*
     * Evalúa únicamente el saldo final para p_rate. Aplica la capitalización
     * y resta cada pago en valor absoluto, desde la segunda posición.
     * Se utiliza en la bisección y en la validación del resultado.
     *
     *   Entrada: p_rate, tasa por período en tanto por uno.
     *   Retorna el residuo monetario firmado después de v_n - 1 períodos.
     *   Comparte la ecuación de f_evaluar sin calcular la derivada.
     */
    FUNCTION f_evaluar_saldo(p_rate IN NUMBER)
      RETURN NUMBER
    IS
      v_saldo NUMBER := v_saldo_ini;
      v_1_p_r NUMBER := 1.0 + p_rate;
    BEGIN
      FOR i IN 2 .. v_n LOOP
        v_saldo := v_saldo * v_1_p_r
                   - ABS(v_pagos(i));
      END LOOP;

      RETURN v_saldo;
    END f_evaluar_saldo;

    /*
     * Evalúa si un candidato satisface los criterios de convergencia.
     * p_f: residuo de la ecuación; p_der: derivada en el candidato;
     * p_tol: tolerancia del residuo, calculada a partir de los importes.
     * Acepta un residuo exactamente cero. En los demás casos exige residuo
     * dentro de tolerancia y corrección estimada ABS(p_f / p_der) <= c_tol_rate.
     * Retorna FALSE ante datos insuficientes o derivada cero con residuo no cero.
     *
     *   La corrección p_f / p_der estima localmente el error de tasa.
     *   La pertenencia al dominio se verifica fuera de esta rutina.
     */
    FUNCTION f_convergio(p_f NUMBER, p_der NUMBER, p_tol NUMBER)
      RETURN BOOLEAN IS
    BEGIN
      IF p_f IS NULL OR p_tol IS NULL THEN
        RETURN FALSE;
      END IF;
      IF p_f = 0 THEN
        RETURN TRUE;
      END IF;
      IF p_der IS NULL OR p_der = 0 THEN
        RETURN FALSE;
      END IF;
      RETURN ABS(p_f) <= p_tol AND ABS(p_f / p_der) <= c_tol_rate;
    END f_convergio;

    /*
     * Busca una raíz desde p_seed, con tolerancia de saldo p_tol_saldo.
     * Reduce el paso a la mitad mientras el factor sea al menos 1E-6;
     * acepta un candidato si está en rango y reduce ABS(saldo_final).
     * Retorna el último candidato; p_ok indica si satisface la convergencia.
     *
     *   Paso: r_nuevo = r - lambda * saldo_final / derivada.
     *   Reemplaza una semilla fuera del rango por 0.1. El llamador también
     *   sustituye previamente una semilla NULL por ese valor.
     *   Termina si la derivada es cero o no consigue un paso aceptable.
     *   Captura división por cero y desbordamiento -1426; un fallo fuera del
     *   intento de paso devuelve p_ok = FALSE para habilitar el respaldo.
     *   El candidato retornado requiere comprobar p_ok antes de utilizarlo.
     */
    FUNCTION f_newton(
        p_seed      IN NUMBER,
        p_tol_saldo IN NUMBER,
        p_ok        OUT BOOLEAN
    ) RETURN NUMBER IS
      v_r             NUMBER := p_seed;
      v_fx            NUMBER;
      v_dfx           NUMBER;
      v_step          NUMBER;
      v_new_r         NUMBER;
      v_new_fx        NUMBER;
      v_dummy_dfx     NUMBER;
      v_lambda        NUMBER;
      v_step_accepted BOOLEAN;
    BEGIN
      p_ok := FALSE;
      v_metodo := 'NEWTON';
      v_iteracion := 0;

      IF v_r <= c_min_rate OR v_r > c_max_rate THEN
        v_r := 0.1;
      END IF;

      FOR iter IN 1 .. c_max_iter LOOP
        v_iteracion := iter;
        f_evaluar(v_r, v_fx, v_dfx);

        IF f_convergio(v_fx, v_dfx, p_tol_saldo) THEN
          p_ok := TRUE;
          RETURN v_r;
        END IF;

        IF v_dfx = 0 THEN
          EXIT;
        END IF;

        v_step          := v_fx / v_dfx;
        v_lambda        := 1.0;
        v_step_accepted := FALSE;

        WHILE v_lambda >= 1E-6 LOOP
          BEGIN
          v_new_r := v_r - v_lambda * v_step;

          IF v_new_r > c_min_rate AND v_new_r <= c_max_rate THEN
            f_evaluar(v_new_r, v_new_fx, v_dummy_dfx);

            IF ABS(v_new_fx) < ABS(v_fx) THEN
              v_step_accepted := TRUE;
              EXIT;
            END IF;
          END IF;

          EXCEPTION WHEN ZERO_DIVIDE OR e_pf_overflow THEN NULL;
          END;
          v_lambda := v_lambda / 2.0;
        END LOOP;

        IF NOT v_step_accepted THEN
          EXIT;
        END IF;

        IF f_convergio(v_new_fx, v_dummy_dfx, p_tol_saldo) THEN
          p_ok := TRUE;
          RETURN v_new_r;
        END IF;

        v_r := v_new_r;
      END LOOP;

      f_evaluar(v_r, v_fx, v_dfx);
      p_ok := f_convergio(v_fx, v_dfx, p_tol_saldo);
      RETURN v_r;
    EXCEPTION
      WHEN ZERO_DIVIDE OR e_pf_overflow THEN
        p_ok := FALSE;
        RETURN v_r;
    END f_newton;

    /*
     * Busca una raíz desde [-0.50, 2]. Puede desplazar el extremo inferior
     * a c_min_rate y duplicar el superior hasta 15 veces, sin exceder c_max_rate.
     * Retorna NULL con p_ok = FALSE si los residuos no tienen signos opuestos
     * y ningún extremo evaluado satisface los controles de aceptación.
     * Durante la bisección acepta residuo cero o exige simultáneamente
     * semiancho <= c_tol_rate y ABS(saldo_final) <= p_tol_saldo.
     *
     *   Después de expandir también comprueba convergencia en los extremos.
     *   Solo acepta el inferior si supera c_min_rate; el superior puede ser
     *   igual a c_max_rate. El llamador vuelve a comprobar esos límites.
     *   Cada punto medio conserva la mitad con cambio de signo del residuo.
     *   No captura localmente excepciones numéricas.
     */
    FUNCTION f_bisection(
        p_tol_saldo IN NUMBER,
        p_ok        OUT BOOLEAN
    ) RETURN NUMBER IS
      v_lo     NUMBER := -0.50;
      v_hi     NUMBER := 2.00;
      v_flo    NUMBER;
      v_fhi    NUMBER;
      v_dlo    NUMBER;
      v_dhi    NUMBER;
      v_mid    NUMBER;
      v_fmid   NUMBER;
      v_expand PLS_INTEGER := 0;
    BEGIN
      p_ok  := FALSE;
      v_metodo := 'BISECCION';
      v_iteracion := 0;
      f_evaluar(v_lo, v_flo, v_dlo);
      f_evaluar(v_hi, v_fhi, v_dhi);

      IF f_convergio(v_flo, v_dlo, p_tol_saldo) THEN
        p_ok := TRUE;
        RETURN v_lo;
      ELSIF f_convergio(v_fhi, v_dhi, p_tol_saldo) THEN
        p_ok := TRUE;
        RETURN v_hi;
      END IF;

      IF SIGN(v_flo) = SIGN(v_fhi) AND v_flo > 0 THEN
        v_lo  := c_min_rate;
        v_flo := f_evaluar_saldo(v_lo);
      END IF;

      WHILE SIGN(v_flo) = SIGN(v_fhi)
            AND v_expand < 15
            AND v_hi < c_max_rate LOOP
        v_hi     := LEAST(v_hi * 2.0, c_max_rate);
        v_fhi    := f_evaluar_saldo(v_hi);
        v_expand := v_expand + 1;
      END LOOP;

      f_evaluar(v_lo, v_flo, v_dlo);
      f_evaluar(v_hi, v_fhi, v_dhi);
      IF v_lo > c_min_rate AND f_convergio(v_flo, v_dlo, p_tol_saldo) THEN
        p_ok := TRUE;
        RETURN v_lo;
      ELSIF v_hi <= c_max_rate AND f_convergio(v_fhi, v_dhi, p_tol_saldo) THEN
        p_ok := TRUE;
        RETURN v_hi;
      END IF;

      IF SIGN(v_flo) = SIGN(v_fhi) THEN
        RETURN NULL;
      END IF;

      FOR iter IN 1 .. c_max_iter LOOP
        v_iteracion := iter;
        v_mid  := (v_lo + v_hi) / 2.0;
        v_fmid := f_evaluar_saldo(v_mid);

        IF v_fmid = 0 OR ((v_hi - v_lo) / 2 <= c_tol_rate
           AND ABS(v_fmid) <= p_tol_saldo) THEN
          p_ok := TRUE;
          RETURN v_mid;
        END IF;

        IF SIGN(v_fmid) = SIGN(v_flo) THEN
          v_lo  := v_mid;
          v_flo := v_fmid;
        ELSE
          v_hi  := v_mid;
          v_fhi := v_fmid;
        END IF;
      END LOOP;

      p_ok := v_fmid = 0 OR ((v_hi - v_lo) <= 2 * c_tol_rate
              AND ABS(v_fmid) <= p_tol_saldo);
      RETURN v_mid;
    END f_bisection;
  BEGIN

    -- Cargar pagos por seq y detectar empates, con colecciones locales.
    SELECT valor_pagos, COUNT(*) OVER (PARTITION BY seq)
    BULK COLLECT INTO v_pagos, v_repeticiones
    FROM TABLE(p_detalles)
    WHERE valor_pagos IS NOT NULL
    ORDER BY seq ASC;

    -- Contar todos los registros seq = 2, incluso con valor_pagos NULL.
    -- MAX extrae el saldo; la validación posterior exige una única fila.
    SELECT COUNT(*), MAX(saldo_inicial)
    INTO v_cant_seq2, v_saldo_ini
    FROM TABLE(p_detalles)
    WHERE seq = 2;

    -- Validar la cantidad de pagos y el saldo inicial.
    v_n := v_pagos.COUNT;
    IF v_n < 2 THEN
      v_error_negocio := TRUE;
      RAISE_APPLICATION_ERROR(-20011, 'Buscar Objetivo: se requieren al menos dos pagos con valor valido.');
    END IF;

    FOR i IN 1 .. v_n LOOP
      IF v_repeticiones(i) > 1 THEN
        v_error_negocio := TRUE;
        RAISE_APPLICATION_ERROR(-20015, 'Buscar Objetivo: orden ambiguo; seq repetido.');
      END IF;
    END LOOP;
    IF v_cant_seq2 > 1 THEN
      v_error_negocio := TRUE;
      RAISE_APPLICATION_ERROR(-20015, 'Buscar Objetivo: existe mas de un registro con seq = 2.');
    END IF;
    IF v_cant_seq2 = 0 THEN
      v_error_negocio := TRUE;
      RAISE_APPLICATION_ERROR(-20012, 'Buscar Objetivo: no existe el registro con seq = 2 para obtener saldo_inicial.');
    END IF;
    IF v_saldo_ini IS NULL OR v_saldo_ini <= 0 THEN
      v_error_negocio := TRUE;
      RAISE_APPLICATION_ERROR(-20012, 'Buscar Objetivo: saldo_inicial de seq = 2 debe ser no nulo y mayor que cero.');
    END IF;

    -- Calcular la tolerancia monetaria y obtener la semilla desde p_tie.
    DECLARE
      v_tol_saldo NUMBER := ABS(v_saldo_ini) * c_tol_rel;
    BEGIN
      v_x := p_tie;

      -- Utilizar 0.1 cuando la TIE no esté disponible o esté fuera del dominio.
      IF v_x IS NULL OR v_x <= c_min_rate OR v_x > c_max_rate THEN
        v_x := 0.1;
      END IF;

      -- Intentar Newton y utilizar bisección si no alcanza convergencia.
      v_x := f_newton(v_x, v_tol_saldo, v_ok);

      IF NOT v_ok THEN
        v_x := f_bisection(v_tol_saldo, v_ok);
      END IF;

      -- Validar la raíz interna y retornar el resultado sin redondear.
      IF v_ok
         AND v_x IS NOT NULL
         AND v_x > c_min_rate
         AND v_x <= c_max_rate
         AND ABS(f_evaluar_saldo(v_x)) <= v_tol_saldo THEN
        RETURN v_x;
      END IF;
    END;

    v_error_negocio := TRUE;
    RAISE_APPLICATION_ERROR(-20014, 'Buscar Objetivo: no se obtuvo una solucion valida dentro de los limites y tolerancias establecidos. Metodo=' || v_metodo || ', Iter=' || v_iteracion);
  EXCEPTION
    WHEN OTHERS THEN
      -- Propagar los errores propios; envolver los inesperados con SQLERRM y traza.
      IF v_error_negocio OR SQLCODE = -20999 THEN
        RAISE;
      END IF;
      RAISE_APPLICATION_ERROR(
        -20999,
        SUBSTRB(
          'Error en calcular_buscar_objetivo: ' || SQLERRM || ' | Metodo:' || v_metodo || ', Iter:' || v_iteracion
          || ' | Trace: ' || DBMS_UTILITY.format_error_backtrace,
          1,
          1900
        ),
        TRUE
      );
  END calcular_buscar_objetivo;
/

SHOW ERRORS FUNCTION calcular_buscar_objetivo

DECLARE
    v_errores PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_errores
    FROM USER_ERRORS
    WHERE name IN ('T_BUSCAR_OBJETIVO_DETALLE', 'T_BUSCAR_OBJETIVO_DETALLES',
                   'CALCULAR_BUSCAR_OBJETIVO')
      AND attribute = 'ERROR';
    IF v_errores > 0 THEN
        RAISE_APPLICATION_ERROR(-20000, 'Existen errores de compilación.');
    END IF;
END;
/
