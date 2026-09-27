# Historial de versiones

Este documento registra los cambios del proyecto. El [README](README.md) describe únicamente su funcionamiento actual. Las entradas no implican la existencia de una etiqueta o una publicación en GitHub.

## 1.1

### Interfaz

- El parámetro de estimación inicial se denomina `p_semilla_inicial` y es opcional: `IN NUMBER DEFAULT 0.1`.
- Si se omite, se pasa `NULL` o se proporciona un valor fuera del dominio, se utiliza `0.1`.
- El proyecto se documenta como una solución independiente, sin referencias a otros proyectos de cálculo de tasas.

### Pruebas

- Se incorporan cinco casos para la semilla: parámetro omitido, llamada por nombre, `NULL`, límite inferior excluido y valor superior al dominio.
- La batería contiene 24 casos.

### Compatibilidad

- Las llamadas por posición mantienen el orden: colección de registros y semilla.
- Las llamadas con el nombre anterior del segundo parámetro deben actualizarse a `p_semilla_inicial`.
- Se conservan las reglas de negocio, los métodos numéricos, las tolerancias y el retorno sin redondeo.

## Base anterior a 1.1

- Función `calcular_buscar_objetivo` con entradas tipadas mediante `t_buscar_objetivo_detalle` y `t_buscar_objetivo_detalles`.
- Búsqueda mediante Newton-Raphson con reducción del paso y bisección como respaldo.
- Retorno de la tasa en tanto por uno, sin redondeo explícito.
- Documentación de reglas de negocio, errores y orden de validación.
- Batería de 19 casos para precisión, selección de pagos, errores de negocio, tasas negativas, bisección y secuencias de 60 y 120 períodos.

Esta base se registra como referencia histórica, sin asignarle una versión o fecha de publicación no documentada.
