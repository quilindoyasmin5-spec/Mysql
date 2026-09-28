USE universidad;

-- ESTRUCTURAS NECESARIAS PARA LOS EJERCICIOS
CREATE TABLE IF NOT EXISTS calificaciones (
    id_matricula INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_alumno INT UNSIGNED NOT NULL,
    id_asignatura INT UNSIGNED NOT NULL,
    id_curso_escolar INT UNSIGNED NOT NULL,
    parcial_1 DECIMAL(4,2),
    parcial_2 DECIMAL(4,2),
    parcial_final DECIMAL(4,2),
    trabajo_practico DECIMAL(4,2),
    fecha_registro DATE,
    UNIQUE KEY uk_calificacion_matricula
        (id_alumno, id_asignatura, id_curso_escolar),
    FOREIGN KEY (id_alumno, id_asignatura, id_curso_escolar)
        REFERENCES alumno_se_matricula_asignatura
        (id_alumno, id_asignatura, id_curso_escolar)
);

CREATE TABLE IF NOT EXISTS historial_calificaciones (
    id_historial INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    id_matricula INT UNSIGNED NOT NULL,
    nota_anterior DECIMAL(4,2),
    nota_nueva DECIMAL(4,2),
    fecha_cambio DATETIME NOT NULL
);

DROP FUNCTION IF EXISTS fnc_calcular_nota_final;
DROP FUNCTION IF EXISTS fnc_obtener_estado_academico;
DROP FUNCTION IF EXISTS fnc_total_creditos_matriculados;
DROP FUNCTION IF EXISTS fnc_promedio_general_asignatura;
DROP FUNCTION IF EXISTS fnc_conteo_asignaturas_aprobadas;

DROP PROCEDURE IF EXISTS sp_guardar_calificacion;
DROP PROCEDURE IF EXISTS sp_generar_acta_curso;
DROP PROCEDURE IF EXISTS sp_matricular_alumno;
DROP PROCEDURE IF EXISTS sp_reasignar_docente;
DROP PROCEDURE IF EXISTS sp_reporte_historico_estudiante;

DROP TRIGGER IF EXISTS trg_calificaciones_normalizar_insert;
DROP TRIGGER IF EXISTS trg_calificaciones_normalizar_update;
DROP TRIGGER IF EXISTS trg_calificaciones_auditoria_update;
DROP TRIGGER IF EXISTS trg_calificaciones_validar_insert;
DROP TRIGGER IF EXISTS trg_calificaciones_validar_update;
DROP TRIGGER IF EXISTS trg_matricula_evitar_duplicado;
DROP TRIGGER IF EXISTS trg_calificaciones_fecha_insert;

DELIMITER //

-- FUNCIONES

CREATE FUNCTION fnc_calcular_nota_final(id_matricula INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE p1 DECIMAL(4,2);
    DECLARE p2 DECIMAL(4,2);
    DECLARE pf DECIMAL(4,2);
    DECLARE tp DECIMAL(4,2);

    SELECT parcial_1, parcial_2, parcial_final, trabajo_practico
    INTO p1, p2, pf, tp
    FROM calificaciones
    WHERE calificaciones.id_matricula = id_matricula;

    IF tp IS NULL THEN
        RETURN ROUND((p1 * 0.20) + (p2 * 0.35) + (pf * 0.45), 2);
    ELSE
        RETURN ROUND((p1 * 0.20) + (p2 * 0.35) + (pf * 0.35) + (tp * 0.10), 2);
    END IF;
END//

CREATE FUNCTION fnc_obtener_estado_academico(id_matricula INT)
RETURNS VARCHAR(20)
READS SQL DATA
BEGIN
    IF fnc_calcular_nota_final(id_matricula) >= 3.00 THEN
        RETURN 'APROBADO';
    ELSE
        RETURN 'REPROBADO';
    END IF;
END//

CREATE FUNCTION fnc_total_creditos_matriculados(
    id_alumno INT,
    id_curso_escolar INT
)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE total_creditos DECIMAL(10,2);

    SELECT COALESCE(SUM(a.creditos),0)
    INTO total_creditos
    FROM alumno_se_matricula_asignatura m
    INNER JOIN asignatura a ON a.id = m.id_asignatura
    WHERE m.id_alumno = id_alumno
      AND m.id_curso_escolar = id_curso_escolar;

    RETURN total_creditos;
END//

CREATE FUNCTION fnc_promedio_general_asignatura(id_asignatura INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE promedio DECIMAL(5,2);

    SELECT COALESCE(
        ROUND(AVG(fnc_calcular_nota_final(c.id_matricula)),2), 0
    )
    INTO promedio
    FROM calificaciones c
    WHERE c.id_asignatura = id_asignatura;

    RETURN promedio;
END//

CREATE FUNCTION fnc_conteo_asignaturas_aprobadas(id_alumno INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE total INT;

    SELECT COUNT(*)
    INTO total
    FROM calificaciones c
    WHERE c.id_alumno = id_alumno
      AND fnc_calcular_nota_final(c.id_matricula) >= 3.00;

    RETURN total;
END//

-- PROCEDIMIENTOS

CREATE PROCEDURE sp_guardar_calificacion(
    IN p_id_matricula INT,
    IN p_parcial_1 DECIMAL(4,2),
    IN p_parcial_2 DECIMAL(4,2),
    IN p_parcial_final DECIMAL(4,2),
    IN p_trabajo_practico DECIMAL(4,2)
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM calificaciones
        WHERE id_matricula = p_id_matricula
    ) THEN
        UPDATE calificaciones
        SET parcial_1 = p_parcial_1,
            parcial_2 = p_parcial_2,
            parcial_final = p_parcial_final,
            trabajo_practico = p_trabajo_practico
        WHERE id_matricula = p_id_matricula;
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No existe la matricula indicada para guardar la calificacion';
    END IF;
END//

CREATE PROCEDURE sp_generar_acta_curso(
    IN p_id_asignatura INT,
    IN p_id_curso_escolar INT
)
BEGIN
    SELECT
        p.nif AS documento,
        CONCAT(p.nombre,' ',p.apellido1,' ',COALESCE(p.apellido2,'')) AS nombre_completo,
        c.parcial_1,
        c.parcial_2,
        c.parcial_final,
        c.trabajo_practico,
        fnc_calcular_nota_final(c.id_matricula) AS nota_final
    FROM calificaciones c
    INNER JOIN persona p ON p.id = c.id_alumno
    WHERE c.id_asignatura = p_id_asignatura
      AND c.id_curso_escolar = p_id_curso_escolar;
END//

CREATE PROCEDURE sp_matricular_alumno(
    IN p_id_alumno INT,
    IN p_id_asignatura INT,
    IN p_id_curso_escolar INT
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM alumno_se_matricula_asignatura
        WHERE id_alumno = p_id_alumno
          AND id_asignatura = p_id_asignatura
          AND id_curso_escolar = p_id_curso_escolar
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El alumno ya esta matriculado en esta asignatura y curso escolar';
    ELSE
        INSERT INTO alumno_se_matricula_asignatura
        VALUES (p_id_alumno,p_id_asignatura,p_id_curso_escolar);
    END IF;
END//

CREATE PROCEDURE sp_reasignar_docente(
    IN p_id_asignatura INT,
    IN p_id_profesor INT,
    IN p_id_departamento INT,
    IN p_id_curso_escolar INT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM curso_escolar
        WHERE id = p_id_curso_escolar
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El curso escolar no existe';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM profesor
        WHERE id_profesor = p_id_profesor
          AND id_departamento = p_id_departamento
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El profesor no pertenece al departamento indicado';
    END IF;

    UPDATE asignatura
    SET id_profesor = p_id_profesor
    WHERE id = p_id_asignatura;
END//

CREATE PROCEDURE sp_reporte_historico_estudiante(IN p_id_alumno INT)
BEGIN
    SELECT
        a.nombre AS asignatura,
        CONCAT(prof.nombre,' ',prof.apellido1,' ',COALESCE(prof.apellido2,'')) AS profesor,
        ce.anyo_inicio,
        ce.anyo_fin,
        fnc_calcular_nota_final(c.id_matricula) AS nota_obtenida
    FROM calificaciones c
    INNER JOIN asignatura a ON a.id = c.id_asignatura
    LEFT JOIN profesor pr ON pr.id_profesor = a.id_profesor
    LEFT JOIN persona prof ON prof.id = pr.id_profesor
    INNER JOIN curso_escolar ce ON ce.id = c.id_curso_escolar
    WHERE c.id_alumno = p_id_alumno
    ORDER BY ce.anyo_inicio, a.nombre;
END//

-- TRIGGERS

CREATE TRIGGER trg_calificaciones_normalizar_insert
BEFORE INSERT ON calificaciones
FOR EACH ROW
BEGIN
    IF NEW.trabajo_practico = 0 THEN
        SET NEW.trabajo_practico = NULL;
    END IF;
END//

CREATE TRIGGER trg_calificaciones_normalizar_update
BEFORE UPDATE ON calificaciones
FOR EACH ROW
BEGIN
    IF NEW.trabajo_practico = 0 THEN
        SET NEW.trabajo_practico = NULL;
    END IF;
END//

CREATE TRIGGER trg_calificaciones_auditoria_update
AFTER UPDATE ON calificaciones
FOR EACH ROW
BEGIN
    IF NOT (OLD.parcial_1 <=> NEW.parcial_1)
       OR NOT (OLD.parcial_2 <=> NEW.parcial_2)
       OR NOT (OLD.parcial_final <=> NEW.parcial_final) THEN
        INSERT INTO historial_calificaciones
            (id_matricula,nota_anterior,nota_nueva,fecha_cambio)
        VALUES
            (NEW.id_matricula,
             NULL,
             fnc_calcular_nota_final(NEW.id_matricula),
             NOW());
    END IF;
END//

CREATE TRIGGER trg_calificaciones_validar_insert
BEFORE INSERT ON calificaciones
FOR EACH ROW
BEGIN
    IF (NEW.parcial_1 IS NOT NULL AND (NEW.parcial_1 < 0 OR NEW.parcial_1 > 5))
       OR (NEW.parcial_2 IS NOT NULL AND (NEW.parcial_2 < 0 OR NEW.parcial_2 > 5))
       OR (NEW.parcial_final IS NOT NULL AND (NEW.parcial_final < 0 OR NEW.parcial_final > 5))
       OR (NEW.trabajo_practico IS NOT NULL AND (NEW.trabajo_practico < 0 OR NEW.trabajo_practico > 5)) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Las notas deben estar entre 0.00 y 5.00';
    END IF;
END//

CREATE TRIGGER trg_calificaciones_validar_update
BEFORE UPDATE ON calificaciones
FOR EACH ROW
BEGIN
    IF (NEW.parcial_1 IS NOT NULL AND (NEW.parcial_1 < 0 OR NEW.parcial_1 > 5))
       OR (NEW.parcial_2 IS NOT NULL AND (NEW.parcial_2 < 0 OR NEW.parcial_2 > 5))
       OR (NEW.parcial_final IS NOT NULL AND (NEW.parcial_final < 0 OR NEW.parcial_final > 5))
       OR (NEW.trabajo_practico IS NOT NULL AND (NEW.trabajo_practico < 0 OR NEW.trabajo_practico > 5)) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Las notas deben estar entre 0.00 y 5.00';
    END IF;
END//

CREATE TRIGGER trg_matricula_evitar_duplicado
BEFORE INSERT ON alumno_se_matricula_asignatura
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM alumno_se_matricula_asignatura
        WHERE id_alumno = NEW.id_alumno
          AND id_asignatura = NEW.id_asignatura
          AND id_curso_escolar = NEW.id_curso_escolar
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se permite una matricula duplicada';
    END IF;
END//

CREATE TRIGGER trg_calificaciones_fecha_insert
BEFORE INSERT ON calificaciones
FOR EACH ROW
BEGIN
    IF NEW.fecha_registro IS NULL THEN
        SET NEW.fecha_registro = CURDATE();
    END IF;
END//

DELIMITER ;
