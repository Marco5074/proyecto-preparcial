/* =====================================================================
   Script de apoyo para capturas - BibliotecaPlanes
   Como usarlo:
   1) Activa el plan de ejecucion real: Ctrl + M
   2) Ejecuta CADA BLOQUE por separado (selecciona y F5), no todo junto.
   3) Despues de cada consulta marcada con [CAPTURA]:
        - pestaña "Plan de ejecucion"  -> captura el plan completo
        - pasa el cursor sobre el operador de acceso a Prestamo (y otros
          si te lo indico) -> captura el tooltip
        - pestaña "Mensajes" -> captura la linea Table '...' logical reads
   4) Nombra tus capturas: A1_antes_plan, A1_antes_tooltip, A1_antes_io, etc.
   ===================================================================== */

USE BibliotecaPlanes;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* ---------------------------------------------------------------------
   PASO 0: LIMPIEZA. Deja las tablas solo con los indices de PK/UNIQUE.
   Borra cualquier indice que hayas creado tu antes (ajusta nombres si
   usaste otros; revisa el resultado de sp_helpindex).
   --------------------------------------------------------------------- */
DROP INDEX IF EXISTS IX_SocioID                 ON Prestamo;
DROP INDEX IF EXISTS IX_Socio_ID_Prestamo       ON Prestamo;
DROP INDEX IF EXISTS IX_Prestamo_Socio_Estado   ON Prestamo;
DROP INDEX IF EXISTS IX_Prestamo_Estado         ON Prestamo;
DROP INDEX IF EXISTS IX_Prestamo_Estado_Socio   ON Prestamo;
DROP INDEX IF EXISTS IX_Prestamo_Fecha          ON Prestamo;
DROP INDEX IF EXISTS IX_Socio_Apellido          ON Socio;
GO

-- Verifica que solo queden indices de PK / UNIQUE   [CAPTURA: resultado]
EXEC sp_helpindex 'Prestamo';
EXEC sp_helpindex 'Socio';
GO


/* =====================================================================
   ACTIVIDAD 1 - Busqueda selectiva sin indice
   ===================================================================== */

-- 1A. ANTES (sin indice en socio_id)
-- [CAPTURA: plan + tooltip del operador sobre Prestamo + Mensajes]
-- Fijate en: operador (Scan), "Number of Rows Read" vs "Actual Number of Rows",
--            Predicate (no Seek Predicate), logical reads.
SELECT prestamo_id, socio_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE socio_id = 308;
GO

-- 1B. Crear indice simple
CREATE NONCLUSTERED INDEX IX_SocioID ON Prestamo (socio_id);
GO

-- 1C. DESPUES
-- [CAPTURA: plan + tooltip + Mensajes]
-- Fijate en: Index Seek + Key Lookup (esta consulta pide columnas que el
--            indice no tiene), filas leidas, logical reads.
SELECT prestamo_id, socio_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE socio_id = 308;
GO


/* =====================================================================
   ACTIVIDAD 2 - Key Lookup
   (conserva IX_SocioID de la actividad 1)
   ===================================================================== */

-- 2A. ANTES: indice solo con socio_id, consulta pide MAS columnas
-- [CAPTURA: plan completo + tooltip del Key Lookup + tooltip del Index Seek + Mensajes]
-- Fijate en: Key Lookup, Nested Loops que los une, "Number of Executions"
--            del Key Lookup, logical reads (suelen subir por los lookups).
SELECT prestamo_id, socio_id, ejemplar_id, empleado_id,
       fecha_prestamo, fecha_devolucion_prevista, fecha_devolucion_real, estado
FROM Prestamo
WHERE socio_id = 308;
GO

-- 2B. Version cubriente con INCLUDE
DROP INDEX IF EXISTS IX_SocioID ON Prestamo;
GO
CREATE NONCLUSTERED INDEX IX_Prestamo_Socio_Cubriente
ON Prestamo (socio_id)
INCLUDE (ejemplar_id, empleado_id, fecha_prestamo,
         fecha_devolucion_prevista, fecha_devolucion_real, estado);
GO

-- 2C. DESPUES
-- [CAPTURA: plan + tooltip del Index Seek + Mensajes]
-- Fijate en: desaparece el Key Lookup, cambian los logical reads.
SELECT prestamo_id, socio_id, ejemplar_id, empleado_id,
       fecha_prestamo, fecha_devolucion_prevista, fecha_devolucion_real, estado
FROM Prestamo
WHERE socio_id = 308;
GO

DROP INDEX IF EXISTS IX_Prestamo_Socio_Cubriente ON Prestamo;
GO


/* =====================================================================
   ACTIVIDAD 3 - Un indice no garantiza un Seek
   ===================================================================== */

-- 3A. ANTES (sin indice en estado)
-- [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, estado
FROM Prestamo
WHERE estado = 'Activo';
GO

-- Dato util para tu analisis: cuantas filas devuelve el filtro vs el total
-- [CAPTURA: resultado]
SELECT
    SUM(CASE WHEN estado = 'Activo' THEN 1 ELSE 0 END) AS filas_activo,
    COUNT(*)                                           AS filas_total
FROM Prestamo;
GO

-- 3B. Crear indice sobre estado
CREATE NONCLUSTERED INDEX IX_Prestamo_Estado ON Prestamo (estado);
GO

-- 3C. DESPUES
-- [CAPTURA: plan + tooltip + Mensajes]
-- Fijate en: ¿uso el indice? ¿Seek o Scan? comparalo con filas_activo / filas_total.
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, estado
FROM Prestamo
WHERE estado = 'Activo';
GO

-- 3D. (opcional, muy didactico) Forzar el indice para ver por que el
--     optimizador lo evita. [CAPTURA: plan + Mensajes] y compara logical reads.
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, estado
FROM Prestamo WITH (INDEX (IX_Prestamo_Estado))
WHERE estado = 'Activo';
GO


/* =====================================================================
   ACTIVIDAD 4 - Indice compuesto
   Estado inicial: dejamos SOLO indice en socio_id y el de estado,
   para ver lo que SQL Server hace con indices individuales.
   ===================================================================== */
CREATE NONCLUSTERED INDEX IX_SocioID ON Prestamo (socio_id);
GO

-- 4A. ANTES (indices individuales)
-- [CAPTURA: plan + tooltips + Mensajes]
-- Fijate en: cual indice uso, y si "estado" aparece como Predicate o Seek Predicate.
SELECT prestamo_id, socio_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE estado = 'Activo' AND socio_id = 308;
GO

-- 4B. Indice compuesto (el que ya habias propuesto)
CREATE NONCLUSTERED INDEX IX_Prestamo_Socio_Estado
ON Prestamo (socio_id, estado)
INCLUDE (fecha_prestamo, fecha_devolucion_prevista);
GO

-- 4C. DESPUES
-- [CAPTURA: plan + tooltip + Mensajes]
-- Fijate en: Seek Predicates con ambas columnas, Number of Rows Read.
SELECT prestamo_id, socio_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE estado = 'Activo' AND socio_id = 308;
GO


/* =====================================================================
   ACTIVIDAD 5 - El orden de las columnas importa
   (usa IX_Prestamo_Socio_Estado de la actividad 4)
   Para aislar el efecto, quitamos los demas indices de prueba.
   ===================================================================== */
DROP INDEX IF EXISTS IX_SocioID          ON Prestamo;
DROP INDEX IF EXISTS IX_Prestamo_Estado  ON Prestamo;
GO

-- 5A. Consulta A con indice (socio_id, estado)  [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, estado
FROM Prestamo
WHERE socio_id = 308;
GO

-- 5B. Consulta B con indice (socio_id, estado)  [CAPTURA: plan + tooltip + Mensajes]
-- Fijate en: ¿Seek o Scan? ¿Que significa que estado NO sea la columna lider?
SELECT prestamo_id, socio_id, estado
FROM Prestamo
WHERE estado = 'Activo';
GO

-- 5C. Orden inverso
DROP INDEX IF EXISTS IX_Prestamo_Socio_Estado ON Prestamo;
GO
CREATE NONCLUSTERED INDEX IX_Prestamo_Estado_Socio ON Prestamo (estado, socio_id);
GO

-- 5D. Consulta A con indice (estado, socio_id)  [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, estado
FROM Prestamo
WHERE socio_id = 308;
GO

-- 5E. Consulta B con indice (estado, socio_id)  [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, estado
FROM Prestamo
WHERE estado = 'Activo';
GO

DROP INDEX IF EXISTS IX_Prestamo_Estado_Socio ON Prestamo;
GO


/* =====================================================================
   ACTIVIDAD 6 - Indices en filtros y JOIN
   ===================================================================== */

-- 6A. ANTES  [CAPTURA: plan COMPLETO + tooltips de cada Scan/Seek + Mensajes]
-- Fijate en: que tabla lee mas (Mensajes muestra una linea por tabla),
--            algoritmo de join (Nested Loops / Hash Match / Merge Join),
--            que indices de PK/UNIQUE ya se estan usando.
SELECT p.prestamo_id, s.nombre, s.apellido,
       p.fecha_prestamo, p.fecha_devolucion_prevista, p.estado
FROM Prestamo AS p
INNER JOIN Socio AS s ON p.socio_id = s.socio_id
WHERE s.apellido = 'Siggin';      -- ojo: en la guia faltan las comillas
GO

-- 6B. Indice para el filtro por apellido (evalua si conviene incluir nombre)
CREATE NONCLUSTERED INDEX IX_Socio_Apellido ON Socio (apellido) INCLUDE (nombre);
GO

-- 6C. DESPUES  [CAPTURA: plan completo + tooltips + Mensajes]
-- Fijate en: ¿cambio el operador sobre Socio?, ¿cambio el join?,
--            ¿Prestamo sigue leyendose igual? (la mejora puede estar solo en el filtro).
SELECT p.prestamo_id, s.nombre, s.apellido,
       p.fecha_prestamo, p.fecha_devolucion_prevista, p.estado
FROM Prestamo AS p
INNER JOIN Socio AS s ON p.socio_id = s.socio_id
WHERE s.apellido = 'Siggin';
GO

-- 6D. (opcional) Indice en la FK de Prestamo para el lado del join
-- Solo si en 6C el problema restante esta en Prestamo.
-- CREATE NONCLUSTERED INDEX IX_Prestamo_SocioID_FK ON Prestamo (socio_id);


/* =====================================================================
   ACTIVIDAD 7 - Rangos de fechas y selectividad
   ===================================================================== */
DROP INDEX IF EXISTS IX_Prestamo_SocioID_FK ON Prestamo;
GO

-- 7A. ANTES (sin indice en fecha_prestamo), rango de un mes
-- [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE fecha_prestamo >= '2026-01-01' AND fecha_prestamo < '2026-02-01';
GO

-- 7B. Crear el indice
CREATE NONCLUSTERED INDEX IX_Prestamo_Fecha
ON Prestamo (fecha_prestamo)
INCLUDE (socio_id, ejemplar_id, fecha_devolucion_prevista, estado);
GO

-- 7C. Rango de un mes (el de la guia)  [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE fecha_prestamo >= '2026-01-01' AND fecha_prestamo < '2026-02-01';
GO

-- 7D. Rango pequeño (~una semana)  [CAPTURA: plan + tooltip + Mensajes]
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE fecha_prestamo >= '2026-01-01' AND fecha_prestamo < '2026-01-08';
GO

-- 7E. Rango amplio (~un año)  [CAPTURA: plan + tooltip + Mensajes]
-- Fijate en: ¿sigue usando el indice? ¿Seek o Scan? ¿Cuantas filas devuelve
--            frente al total?
SELECT prestamo_id, socio_id, ejemplar_id, fecha_prestamo, fecha_devolucion_prevista, estado
FROM Prestamo
WHERE fecha_prestamo >= '2026-01-01' AND fecha_prestamo < '2027-01-01';
GO

DROP INDEX IF EXISTS IX_Prestamo_Fecha ON Prestamo;
GO


/* =====================================================================
   ACTIVIDAD 8 - Caso integrador
   Aqui NO te doy el indice: es tu diagnostico.
   ===================================================================== */

-- 8A. ESTADO ORIGINAL (limpia, solo indices PK/UNIQUE)
-- [CAPTURA: plan COMPLETO + tooltip de CADA operador de acceso a tablas
--           + todas las lineas Table '...' de Mensajes]
SELECT s.nombre, s.apellido, l.titulo,
       p.fecha_prestamo, p.fecha_devolucion_prevista, p.estado
FROM Prestamo AS p
INNER JOIN Socio    AS s ON p.socio_id    = s.socio_id
INNER JOIN Ejemplar AS e ON p.ejemplar_id = e.ejemplar_id
INNER JOIN Libro    AS l ON e.libro_id    = l.libro_id
WHERE p.estado = 'Vencido'
  AND p.fecha_devolucion_prevista >= '2026-01-01'
  AND p.fecha_devolucion_prevista <  '2026-04-01';
GO

-- 8B. Tu propuesta: escribe aqui tus CREATE INDEX (solo si puedes justificarlos
--     con la evidencia de 8A), crea UNO a la vez, y repite la consulta de 8A.

-- 8C. Al terminar, limpia con DROP INDEX IF EXISTS <tus_indices> ON <tabla>;
