# Porcentaje Buscar Objetivo en Oracle PL/SQL

Función **Oracle PL/SQL** que calcula la tasa por período necesaria para amortizar un saldo inicial mediante una secuencia de pagos, hasta obtener un saldo final cero dentro de las tolerancias establecidas.

La función `calcular_buscar_objetivo` recibe una colección tipada y una tasa de interés efectiva (TIE) como estimación inicial de la tasa. Retorna un `NUMBER` en tanto por uno, **sin redondear la tasa**: `0.1` representa un **10 % por período**.

## Archivos

| Archivo | Contenido |
| --- | --- |
| [porcentaje_buscar_objetivo.sql](porcentaje_buscar_objetivo.sql) | Tipos de entrada, función y verificación de compilación. |
| [test_porcenaje_buscar_objetivo.sql](test_porcenaje_buscar_objetivo.sql) | 19 casos de prueba con aserciones de tasas, residuos y errores. |
| [README.md](README.md) | Reglas de negocio, instalación y uso. |

## Reglas de negocio

**Las reglas de negocio definen la selección de registros, el saldo de partida y la aplicación de los pagos.**

| Regla | Comportamiento |
| --- | --- |
| Caso a calcular | La colección debe contener únicamente los registros de la operación que se desea evaluar. La selección de esos registros corresponde a la aplicación que invoca la función. |
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

El primer script crea o reemplaza los tipos `t_buscar_objetivo_detalle`, `t_buscar_objetivo_detalles` y la función `calcular_buscar_objetivo`. Muestra los errores de compilación y comprueba `USER_ERRORS`. El segundo ejecuta las pruebas de negocio y convergencia.

La función trabaja exclusivamente con los parámetros de entrada y no depende de tablas ni de funciones externas de cálculo financiero.

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

### Semilla e integración opcional

`p_tie` puede proceder de un cálculo externo, como `calcular_tir_no_per` del proyecto `tir-no-periodica`. Los códigos `-20004`, `-20005`, `-20006`, `-20007` y `-20008` citados en el comentario de la función corresponden a ese cálculo externo; no son errores emitidos por `calcular_buscar_objetivo`.

Si la aplicación trata esos errores como una semilla no disponible, puede pasar `NULL` para utilizar el respaldo `0.1`. Los demás errores de obtención deben gestionarse en la aplicación que prepara los parámetros. La integración es opcional: esta función no invoca `calcular_tir_no_per` ni requiere instalar el otro proyecto.

La semilla se expresa en tanto por uno. Una tasa obtenida con otra periodicidad solo actúa como estimación inicial; la tasa retornada corresponde a los períodos de los pagos recibidos.

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

### Expansión hacia tasas menores que -0.50

Con saldo inicial `S > 0`, `m` períodos, pagos absolutos `A_k >= 0` y `x = 1 + r > 0`, el residuo final puede escribirse como:

```text
F(r) = x^m × [S − SUM(A_k / x^k)], k = 1 .. m
```

El factor `x^m` es positivo. La expresión entre corchetes es estrictamente creciente en `r` cuando existe algún pago aplicado positivo. Por tanto, tiene como máximo una raíz y determina el signo del residuo a ambos lados de ella. Esto no requiere que el propio residuo `F` sea creciente en todo el dominio.

Si la raíz está por debajo de `-0.50`, los residuos en `-0.50` y `2` son positivos. Esa es precisamente la condición que desplaza el extremo inferior a `-0.99999999`. Tener ambos residuos negativos y una raíz inferior a `-0.50` es incompatible con estas reglas de negocio. Cuando todos los pagos aplicados son cero, el residuo permanece positivo y no existe raíz en el dominio admitido.

La prueba con saldo `100`, pagos `20` y `3`, y semilla `-0.9` obliga a abandonar Newton por derivada cero. Los residuos de los extremos iniciales son `12` y `837`; la bisección debe ampliar el intervalo hacia abajo y encontrar la tasa `-0.7`.

## Errores

| Código | Motivo |
| --- | --- |
| `-20011` | Menos de dos pagos con valor no nulo. |
| `-20012` | Falta el registro con `seq = 2`, o su saldo es `NULL`, cero o negativo. |
| `-20014` | No se obtiene una solución válida dentro de los límites y tolerancias. |
| `-20015` | `seq` repetido entre los pagos filtrados o más de un registro con `seq = 2`. |
| `-20999` | Error inesperado; incluye el error original y la traza de ejecución. |

### Prioridad de las validaciones

Las validaciones se ejecutan en el siguiente orden. La primera condición incumplida determina el error retornado:

1. Cantidad de pagos no nulos: `-20011` si quedan menos de dos.
2. Valores de `seq` repetidos en los pagos filtrados: `-20015`.
3. Más de un registro con `seq = 2`, incluidos los de pago nulo: `-20015`.
4. Ausencia de un registro con `seq = 2`: `-20012`.
5. Saldo inicial nulo, cero o negativo: `-20012`.
6. Búsqueda y validación numérica: `-20014` si no se obtiene una solución dentro del dominio y las tolerancias.

Por ejemplo, un único pago retenido y dos registros con `seq = 2` producen `-20011`. Dos pagos con `seq` repetido y sin un registro `seq = 2` producen `-20015`. Los errores inesperados durante el procesamiento se gestionan mediante `-20999`.

## Pruebas

Después de instalar los tipos y la función, ejecutar:

```sql
@test_porcenaje_buscar_objetivo.sql
```

El script contiene **19 casos**. Cada caso satisfactorio muestra `OK`; cualquier aserción fallida genera `-20000` y detiene la ejecución en un cliente compatible con SQL*Plus.

| Cobertura | Comprobaciones |
| --- | --- |
| Precisión de salida | Tasa `1/3` sin redondeo a 16 decimales y residuo dentro de tolerancia. |
| Selección de registros | Ordenación, pago nulo, valor absoluto y saldo tomado de un registro con pago nulo. |
| Cantidad mínima | Error `-20011` después de filtrar pagos nulos. |
| Saldo inicial | Error `-20012` por ausencia de `seq = 2`, saldo nulo, cero y negativo, en casos independientes. |
| Solución fuera del dominio | Error `-20014` para una raíz de `101` y para pagos aplicados todos iguales a cero. |
| Duplicados | Error `-20015` por secuencia repetida entre pagos y por `seq = 2` duplicado con un pago nulo. |
| Prioridad de validaciones | Cantidad insuficiente antes de duplicados; duplicados antes de ausencia del saldo. |
| Pago cero intermedio | Saldo `100`, pagos `0` y `121`: tasa `0.1` para dos períodos. |
| Tasa negativa | Saldo `100`, pago `80`: tasa `-0.2`, conservando el signo. |
| Respaldo por bisección | Saldo `100`, pagos `40` y `5`, semilla `-0.8`: derivada cero con residuo `-9`; resultado esperado `-0.5`. |
| Expansión inferior de bisección | Saldo `100`, pagos `20` y `3`, semilla `-0.9`: derivada cero con residuo `-4`; resultado esperado `-0.7`. |
| Secuencias largas | 60 y 120 pagos de `1000`, saldo construido por descuento al `1 %`, semilla `0.02` y tasa esperada `0.01`. |

Los casos de bisección comprueban que la derivada inicial es exactamente cero y que el residuo no lo es. Estas condiciones obligan a Newton a terminar sin converger, de modo que la solución posterior debe proceder del respaldo. El segundo caso exige también iteraciones dentro del intervalo ampliado, ya que la raíz no coincide con sus extremos.

Cada caso de tasa comprueba el dominio, una diferencia respecto a la tasa esperada no mayor que `1E-18` y un residuo final no mayor que `ABS(saldo_inicial) × 1E-18`. Las secuencias largas construyen el saldo mediante descuento inverso, sin `POWER` ni una semilla igual a la raíz esperada. Las tolerancias se mantienen en `1E-18`; los resultados se verifican con la aritmética `NUMBER` de la instancia Oracle donde se ejecute el script.

Al completar todos los casos, el script muestra `Pruebas correctas: 19 casos.`. Esta cobertura se centra en errores de negocio y convergencia; no incluye la provocación deliberada de errores inesperados `-20999`.
