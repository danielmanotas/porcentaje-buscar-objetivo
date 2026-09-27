# Guía para ejecutar pruebas

La batería comprueba la función `calcular_buscar_objetivo` con la aritmética `NUMBER` de Oracle. Contiene 24 casos y no inserta datos ni modifica tablas de negocio.

## Requisitos

- Acceso a una base de datos Oracle y a un esquema destinado a pruebas.
- Permisos `CREATE TYPE` y `CREATE PROCEDURE` para instalar los objetos.
- SQL*Plus o un cliente compatible con sus comandos de script; también puede utilizarse SQL Developer mediante **Ejecutar script (F5)**.
- Los archivos `porcentaje_buscar_objetivo.sql` y `test_porcenaje_buscar_objetivo.sql` en la misma carpeta.

La instalación crea o reemplaza dos tipos y una función. Utilizar un esquema de pruebas sin objetos homónimos que deban conservarse. Las instrucciones DDL no se revierten mediante el `ROLLBACK` del manejador de errores del script.

## Instalar y ejecutar

Conectar al esquema de pruebas. Desde la carpeta que contiene los scripts, ejecutar en este orden:

```sql
@porcentaje_buscar_objetivo.sql
@test_porcenaje_buscar_objetivo.sql
```

En SQL Developer, abrir y ejecutar primero el archivo de instalación y después el de pruebas con **F5**. Revisar la salida del script, no solamente la cuadrícula de resultados.

El instalador muestra errores de compilación y consulta `USER_ERRORS`. No continuar con las pruebas si la instalación falla.

## Resultado esperado

Cada caso satisfactorio imprime una línea `OK`. Los casos que comparan tasas también muestran la tasa y el residuo. La última línea debe ser:

```text
Pruebas correctas: 24 casos.
```

Una aserción fallida genera `-20000`. Los scripts contienen `WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK`, por lo que SQL*Plus finaliza ante un error no capturado. Los errores de negocio esperados se capturan y comparan dentro de cada prueba; no representan fallos cuando coinciden con el código previsto.

Para conservar la salida en SQL*Plus:

```sql
SPOOL resultado_pruebas.log
@porcentaje_buscar_objetivo.sql
@test_porcenaje_buscar_objetivo.sql
SPOOL OFF
```

El archivo de salida es un resultado local de ejecución y no forma parte de los archivos fuente del proyecto.

## Cobertura

| Grupo | Casos | Qué comprueba |
| --- | ---: | --- |
| Precisión y selección de registros | 2 | Tasa sin redondeo, orden, pagos nulos y valores absolutos. |
| Errores y prioridad de validaciones | 11 | Cantidad, saldo, duplicados, ausencia de solución y orden de errores. |
| Pago cero y tasa negativa | 2 | Capitalización de un período con pago cero y conservación del signo. |
| Bisección | 2 | Respaldo por derivada cero y expansión hacia una raíz menor que `-0.50`. |
| Secuencias largas | 2 | Convergencia con 60 y 120 períodos. |
| Semilla inicial | 5 | Parámetro omitido, nombre público, `NULL` y valores fuera del dominio. |
| **Total** | **24** | |

La suite no provoca deliberadamente errores inesperados `-20999` ni demuestra convergencia para todas las posibles entradas.

## Criterios numéricos

- Dominio del resultado: `-0.99999999 < r <= 100`.
- Diferencia respecto a la tasa esperada: como máximo `1E-18` en los casos que utilizan el verificador común.
- Residuo final: como máximo `ABS(saldo_inicial) × 1E-18`.
- Sin redondeo explícito de la tasa retornada.

Los casos de bisección utilizan semillas con derivada exactamente cero y residuo no nulo. Eso obliga a Newton a abandonar la búsqueda y permite comprobar el respaldo sin añadir parámetros de prueba a la función.

## Diagnóstico de fallos

Si aparecen errores de compilación, revisar:

```sql
SELECT name, type, line, position, text
FROM user_errors
WHERE name IN (
    'T_BUSCAR_OBJETIVO_DETALLE',
    'T_BUSCAR_OBJETIVO_DETALLES',
    'CALCULAR_BUSCAR_OBJETIVO'
)
ORDER BY name, sequence;
```

Ante una prueba fallida, conservar el nombre del caso, el código y mensaje completos, la tasa y el residuo disponibles, y la versión de Oracle. Verificar que la función instalada corresponda a los archivos probados. No modificar tolerancias sin una evaluación numérica del fallo.

Una simulación con aritmética decimal en otro lenguaje puede servir de apoyo, pero la confirmación de estas pruebas requiere ejecutarlas en Oracle. La existencia del script no certifica que se haya ejecutado satisfactoriamente en una instalación concreta.
