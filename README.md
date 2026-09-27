# porcentaje-buscar-objetivo

Función **Oracle PL/SQL** que calcula la tasa por período necesaria para amortizar un saldo inicial mediante una secuencia de pagos, hasta obtener un saldo final cero dentro de las tolerancias establecidas.

Recibe una colección tipada y una TIE como semilla. Retorna un `NUMBER` en tanto por uno, **sin redondear la tasa**: `0.1` representa un **10 % por período**.

## Archivos

| Archivo | Contenido |
| --- | --- |
| [porcentaje_buscar_objetivo.sql](porcentaje_buscar_objetivo.sql) | Tipos de entrada, función y verificación de compilación. |
| [test_porcenaje_buscar_objetivo.sql](test_porcenaje_buscar_objetivo.sql) | Pruebas con aserciones y ejemplo de uso. |
| [README.md](README.md) | Reglas de negocio, instalación y uso. |

## Reglas de negocio

**Estas reglas determinan qué registros participan y cómo se aplica cada pago. Se conservan del proceso original.**

| Regla | Comportamiento |
| --- | --- |
| Caso a calcular | El llamador debe seleccionar los registros del caso antes de construir la colección. La función ya no filtra por empresa, registro o novedad. |
| Pago nulo | Un registro con `valor_pagos IS NULL` se excluye de la lista de pagos y no genera período. Sigue participando en la búsqueda y validación del saldo inicial. |
| Cantidad mínima | Deben existir al menos dos registros con pago no nulo, después del filtrado. |
| Orden de aplicación | Los pagos se ordenan por `seq` ascendente, independientemente del orden de entrada. |
| Primera posición | Se omite siempre la primera posición de la lista filtrada, aunque su `seq` no sea 1. Su pago no se descuenta. |
| Saldo inicial | Se toma del único registro con `seq = 2`, incluso si su pago es nulo. Debe ser no nulo y estrictamente positivo. No se redondea ni se transforma con `ABS`. |
| Duplicados | Se rechazan los valores de `seq` repetidos entre los pagos no nulos. También se rechaza más de un registro con `seq = 2`, aunque alguno tenga pago nulo. |
| Secuencias | No se exigen valores consecutivos de `seq` ni que la segunda posición tenga `seq = 2`. La posición filtrada y el valor de `seq` son conceptos distintos. |
| Signo del pago | Cada pago aplicado se toma en valor absoluto: un pago de `-110` tiene el mismo efecto que uno de `110`. |
| Pago cero | Se conserva y genera un período cuando está después de la primera posición. Capitaliza el saldo, aunque no descuenta importe. |
| Número de períodos | Con `n` pagos retenidos se aplican `n - 1` períodos. No se calculan diferencias entre fechas. |
| Saldos intermedios | No se redondean ni se exige que sean positivos. |
| Periodicidad de la tasa | Depende de los períodos representados por los pagos. La tasa solo es mensual si cada posición aplicada corresponde a un mes. |
| Resultado | Se devuelve la raíz validada, sin redondeo de salida y con la precisión propia de Oracle `NUMBER`. |

### Ejemplo del tratamiento de registros

| `seq` | `valor_pagos` | `saldo_inicial` | Efecto |
| --- | --- | --- | --- |
| 1 | 0 | `NULL` | Primera posición filtrada: se omite. |
| 2 | `NULL` | 100 | Aporta el saldo inicial; no genera período. |
| 5 | -110 | `NULL` | Se aplica como pago de 110 al final de un período. |

Aunque las secuencias no son consecutivas, este caso representa **un solo período**. La tasa que satisface `100 × (1 + r) − 110 = 0` es `0.1`.

## Instalación

Se requiere una base de datos Oracle, permisos `CREATE TYPE` y `CREATE PROCEDURE` en el esquema de destino, y un cliente compatible con scripts SQL*Plus. En SQL Developer, usar **Ejecutar script (F5)**.

Desde la carpeta del repositorio, ejecutar en este orden:

```sql
@porcentaje_buscar_objetivo.sql
@test_porcenaje_buscar_objetivo.sql
```

El primer script crea o reemplaza los tipos `t_buscar_objetivo_detalle`, `t_buscar_objetivo_detalles` y la función `calcular_buscar_objetivo`. Muestra los errores de compilación y comprueba `USER_ERRORS`. El segundo ejecuta las pruebas y un ejemplo.

No se requieren tablas de negocio ni la función `pf_calcular_tie` para instalar o ejecutar estos archivos.

## Parámetros

```sql
calcular_buscar_objetivo(
    p_detalles IN t_buscar_objetivo_detalles,
    p_tie      IN NUMBER
) RETURN NUMBER
```

| Parámetro | Descripción |
| --- | --- |
| `p_detalles` | Colección de registros del caso, incluidos aquellos cuyo pago es `NULL`. |
| `p_tie` | TIE previamente calculada, en tanto por uno, utilizada como semilla. Pasar `NULL` cuando no esté disponible. |

Cada elemento se construye con `t_buscar_objetivo_detalle(seq, valor_pagos, saldo_inicial)`:

| Atributo | Tipo | Uso |
| --- | --- | --- |
| `seq` | `NUMBER` | Orden de los pagos e identificación del registro con `seq = 2`. |
| `valor_pagos` | `NUMBER` | Importe del pago; se aplica en valor absoluto después del filtrado. |
| `saldo_inicial` | `NUMBER` | Saldo de partida; se utiliza únicamente el del registro con `seq = 2`. |

La colección debe estar inicializada y contener objetos construidos. Una colección vacía no satisface el mínimo de pagos. El llamador debe preparar los datos y la TIE dentro del contexto transaccional apropiado si deben reflejar una misma instantánea.

## Ejemplo de uso

Un saldo de **100** y un pago de **110** al final de un período requieren una tasa de **0.1**:

```sql
SET SERVEROUTPUT ON

DECLARE
    v_detalles t_buscar_objetivo_detalles := t_buscar_objetivo_detalles(
        t_buscar_objetivo_detalle(1,   0, NULL),
        t_buscar_objetivo_detalle(2, 110,  100)
    );
    v_tasa NUMBER;
BEGIN
    v_tasa := calcular_buscar_objetivo(
        p_detalles => v_detalles,
        p_tie      => NULL
    );
    DBMS_OUTPUT.PUT_LINE('Tasa por período: ' || TO_CHAR(v_tasa));
END;
/
```

La primera posición se omite. La segunda aporta el saldo inicial de 100 y el pago de 110. El resultado se devuelve en tanto por uno; para expresarlo como porcentaje, el consumidor puede multiplicarlo por 100.

## Método y tolerancias

Para cada pago aplicado, se capitaliza el saldo y después se descuenta el importe absoluto:

```text
saldo_nuevo = saldo_anterior × (1 + r) − ABS(pago)
```

Se busca una tasa cuyo saldo final satisfaga la tolerancia. Primero se utiliza **Newton-Raphson con reducción del paso**; si no converge, se utiliza **bisección con expansión acotada del intervalo**.

| Parámetro numérico | Valor |
| --- | --- |
| Dominio de la tasa | `-0.99999999 < r <= 100` |
| Iteraciones máximas | `100` por método |
| Tolerancia del saldo | `ABS(saldo_inicial) × 1E-18` |
| Tolerancia absoluta de tasa | `1E-18` |
| Semilla de respaldo | `0.1` |

Se utiliza `p_tie` si está dentro del dominio; si es `NULL` o está fuera de él, se utiliza `0.1`. La TIE solo guía la búsqueda inicial y no determina la periodicidad del resultado.

Newton acepta un residuo cero o exige simultáneamente la tolerancia del saldo y una corrección estimada de tasa dentro de tolerancia. La bisección comprueba el residuo y la amplitud del intervalo. Antes de retornar, la función verifica convergencia, dominio y residuo final.

La ausencia de redondeo explícito conserva la precisión disponible de `NUMBER`; no implica precisión infinita.

## Errores

| Código | Motivo |
| --- | --- |
| `-20011` | Menos de dos pagos con valor no nulo. |
| `-20012` | Falta el registro con `seq = 2`, o su saldo es `NULL`, cero o negativo. |
| `-20014` | No se obtiene una solución válida dentro de los límites y tolerancias. |
| `-20015` | `seq` repetido entre los pagos filtrados o más de un registro con `seq = 2`. |
| `-20999` | Error inesperado; incluye el error original y la traza de ejecución. |

## Cambios respecto al original

Las cinco rutinas numéricas internas se conservan literalmente. Los cambios se limitan a recibir la colección y la TIE por parámetros, consultar esa colección en lugar de las tablas, devolver `v_x` sin redondearlo y ajustar la documentación y el contexto del error inesperado.

El error `-20013` desaparece porque ya no existe el parámetro de selección de origen. La obtención de la TIE queda a cargo del llamador: para conservar el respaldo original, debe pasar `NULL` si `pf_calcular_tie` produce `-20004`, `-20005`, `-20006`, `-20007` o `-20008`. Los demás errores de obtención deben gestionarse antes de invocar esta función.

## Pruebas y estado de validación

El archivo de pruebas comprueba:

- Una tasa de `1/3`, su residuo y la conservación de decimales más allá de las 16 posiciones.
- La ordenación, la exclusión de pagos nulos, el uso de pagos absolutos y la obtención del saldo desde un registro con pago nulo.
- El error `-20015` ante un registro `seq = 2` duplicado.

Si las aserciones pasan, muestra `Pruebas correctas.` y ejecuta el ejemplo de saldo 100 y pago 110. Ante un fallo, propaga el error.

**Estado de validación:** se verificó estáticamente la conservación del código numérico. La compilación y las pruebas en Oracle están pendientes de ejecución; no se dispuso de una conexión Oracle en el entorno de preparación.
