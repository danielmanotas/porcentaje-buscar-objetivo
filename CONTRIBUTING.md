# Guía de colaboración

Las contribuciones pueden incluir correcciones, pruebas, documentación y mejoras del cálculo. Antes de proponer un cambio, revisar las reglas de negocio del [README](README.md) y la [guía de pruebas](TESTING.md).

## Preparar una contribución

1. Crear un fork del repositorio y una rama con un nombre descriptivo.
2. Reproducir el problema con datos sintéticos o públicos.
3. Realizar un cambio limitado al problema identificado.
4. Añadir o ajustar las pruebas que comprueban el comportamiento afectado.
5. Ejecutar la instalación y la batería de pruebas en Oracle.
6. Abrir un pull request con el motivo del cambio y los resultados de validación.

Ejemplo de preparación local:

```bash
git clone https://github.com/TU_USUARIO/porcentaje-buscar-objetivo.git
cd porcentaje-buscar-objetivo
git switch -c mejora/descripcion-breve
```

Sustituir `TU_USUARIO` por la cuenta propietaria del fork.

## Criterios del proyecto

- Mantener el código y la documentación en el estilo existente, con comentarios en español.
- Conservar la aritmética `NUMBER` y el retorno sin redondeo explícito.
- Mantener coherentes la firma, las llamadas de ejemplo y las pruebas.
- Documentar cualquier modificación de reglas de negocio, límites, tolerancias o prioridad de errores y justificarla con casos reproducibles.
- No reducir la precisión para hacer pasar una prueba sin analizar la causa numérica.
- Mantener la semilla como una estimación general, sin introducir dependencias de otros proyectos.
- Usar datos sintéticos; no incluir credenciales, conexiones privadas ni información financiera confidencial.

## Pruebas

Seguir [TESTING.md](TESTING.md). Una contribución debe indicar qué pruebas se ejecutaron y en qué versión de Oracle y cliente. Si no se pudo ejecutar Oracle, declararlo expresamente; una revisión estática o una simulación en otro lenguaje no equivale a validar la implementación PL/SQL.

Las pruebas nuevas deben comprobar un comportamiento observable: tasa esperada, residuo, dominio o código de error. Cuando se compruebe una vía numérica específica, documentar las condiciones que obligan a recorrerla.

## Documentación y versiones

- El [README](README.md) presenta la versión actual como documentación general, sin una lista de novedades.
- El [historial](CHANGELOG.md) concentra los cambios entre versiones.
- Mantener sincronizados el número de casos y los ejemplos cuando cambien las pruebas.
- No asignar fechas de publicación ni etiquetas de GitHub que todavía no existan.

## Contenido del pull request

Incluir una explicación breve del problema, el comportamiento resultante, las pruebas realizadas y cualquier impacto sobre llamadas existentes. Para cambios numéricos, aportar datos de entrada, semilla, tasa esperada, residuo obtenido y tolerancia utilizada.

## Reportar un problema

Abrir un issue con la versión del proyecto, versión de Oracle, mensaje completo de error y un bloque SQL mínimo que reproduzca el caso. Utilizar datos sintéticos e indicar el resultado esperado y el observado.

## Licencia

Las contribuciones se incorporan bajo la [licencia MIT](LICENSE.md) del proyecto. Quien contribuya debe tener derecho a compartir el código y los datos incluidos.
