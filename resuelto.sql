/* ============================================================================
1. Agregar las relaciones
============================================================================= */

-- Tabla Publicación
ALTER TABLE Publicacion ADD INDEX(id_tipo);
ALTER TABLE Publicacion ADD CONSTRAINT `publicacion_fk_tipo` FOREIGN KEY (id_tipo) REFERENCES Tipo(id) ON DELETE RESTRICT ON UPDATE RESTRICT; 

-- Tabla Venta
ALTER TABLE Venta ADD INDEX(id_empleado);
ALTER TABLE Venta ADD INDEX(id_canal);
ALTER TABLE Venta ADD INDEX(id_publicacion);
ALTER TABLE Venta ADD INDEX(id_promocion);
ALTER TABLE Venta ADD CONSTRAINT `ventan_fk_empleado` FOREIGN KEY (id_empleado) REFERENCES Empleado(id) ON DELETE RESTRICT ON UPDATE RESTRICT; 
ALTER TABLE Venta ADD CONSTRAINT `ventan_fk_canal` FOREIGN KEY (id_canal) REFERENCES Canal_Venta(id) ON DELETE RESTRICT ON UPDATE RESTRICT; 
ALTER TABLE Venta ADD CONSTRAINT `ventan_fk_publicacion` FOREIGN KEY (id_publicacion) REFERENCES Publicacion(id) ON DELETE RESTRICT ON UPDATE RESTRICT; 


-- FIX problema de que el id por defecto quedo mal en la columna 'promoción' en la tabla 'Venta'
UPDATE Venta
	SET id_promocion = 1;

ALTER TABLE Venta ADD CONSTRAINT `ventan_fk_promocion` FOREIGN KEY (id_promocion) REFERENCES Promocion(id) ON DELETE RESTRICT ON UPDATE RESTRICT; 

/* ============================================================================
2. Obtener la cantidad de Ventas en los últimos meses (Venta = Cantidad * Precio)
============================================================================= */
SELECT 
	YEAR(fecha) AS ANIO, MONTH(fecha) AS MES, 
	SUM(cantidad * precio) as Ventas
FROM Venta
GROUP BY YEAR(fecha), MONTH(fecha)
ORDER BY YEAR(fecha), MONTH(fecha);

-- 2. ¡BONUS TRACK! Saber la cantidad de Ventas Y COSTOS en los últimos meses (Costo = Costo * Cantidad)
-- Metodo JOIN (hay otro Metodo??)
SELECT 
	YEAR(v.fecha), MONTH(v.fecha), 
	SUM(v.cantidad * v.precio) as Ventas,
	SUM(p.costo * v.cantidad) as Costo
FROM Venta v
	JOIN Publicacion p ON v.id_publicacion = p.id
GROUP BY YEAR(v.fecha), MONTH(v.fecha)
ORDER BY YEAR(v.fecha), MONTH(v.fecha);


/* ============================================================================
3. Encontrar el Empleado que más vendió (y menos) en promedio en los últimos meses
============================================================================= */
SELECT e.nombre, AVG(v.precio * v.cantidad) as Ventas
FROM Empleado e
	JOIN Venta v ON v.id_empleado = e.id
GROUP BY e.nombre
ORDER BY Ventas DESC;

/* ============================================================================
4. Encontrar el producto que más se vendió y cual el que menos se vendió
============================================================================= */

SELECT 
	p.titulo, p.autor,
	SUM(v.precio * v.cantidad) as Ventas
FROM
	Publicacion p
JOIN 
	Venta v ON v.id_publicacion = p.id
GROUP BY p.titulo, p.autor
ORDER BY Ventas DESC;


-- 4. ¡BONUS TRACK! Encontrar el producto que más se vendió y 
-- cual el que menos se vendió de la categoría 'Revista'

SELECT 
	p.titulo, p.autor,
	SUM(v.precio * v.cantidad) as Ventas
FROM
	Publicacion p
JOIN 
	Venta v ON v.id_publicacion = p.id
WHERE
	p.id_tipo = 'REV'
GROUP BY p.titulo, p.autor
ORDER BY Ventas DESC;

/* ============================================================================
5. Transformar la consulta anterior en un StoreProcedure que reciba como parámetro
   el tipo de Publicación
============================================================================= */


DROP PROCEDURE IF EXISTS selec_promedio_tipo;
DELIMITER $$
CREATE PROCEDURE selec_promedio_tipo (IN tipe VARCHAR(255))
BEGIN  
	SELECT 
		p.titulo, p.autor,
		SUM(v.precio * v.cantidad) as Ventas
	FROM
		Publicacion p
	JOIN 
		Venta v ON v.id_publicacion = p.id
	WHERE
		p.id_tipo = tipe COLLATE UTF8MB4_SPANISH_CI
	GROUP BY p.titulo, p.autor
	ORDER BY Ventas DESC;
END$$
DELIMITER ;

CALL selec_promedio_tipo('LIB');


/* ============================================================================
6. Crear una FUNCION que implemente la aplicación de las promociones 
   (recibe producto, cantidad -> retorna id de promoción)
============================================================================= */


DROP FUNCTION IF EXISTS promocion_descuento;
DELIMITER $$
CREATE FUNCTION promocion_descuento (publicacion_id INTEGER, cantidad INTEGER) RETURNS INTEGER
BEGIN
	
	SET @tipo = (SELECT id_tipo FROM Publicacion WHERE id = publicacion_id);
	SET @descuento = IFNULL(
		(SELECT id FROM Promocion WHERE cantidad BETWEEN cant_min AND cant_max AND tipo = @tipo),
        1
    );
	RETURN @descuento;
END$$
DELIMITER ;

SELECT promocion_descuento(2, 8);

/* ============================================================================
7. Crear un Trigger, que utilice la función anterior, para guardar el producto con descuento (si aplica)
   cuando agreguemos una venta
============================================================================= */
DROP TRIGGER IF EXISTS insert_venta;
DELIMITER $$
CREATE TRIGGER insert_venta BEFORE INSERT
	ON Venta
	FOR EACH ROW BEGIN
		SET @promocion = promocion_descuento(NEW.id_publicacion, NEW.cantidad);
        SET @descuento = (SELECT porcentaje FROM Promocion WHERE id = @promocion);
        SET @precio = (SELECT precio FROM Publicacion WHERE id = NEW.id_publicacion);
		SET NEW.precio = @precio * (1 - @descuento);
        SET NEW.id_promocion = @promocion;
	END$$
DELIMITER ;

INSERT INTO 
	Venta (fecha,id_empleado,id_publicacion,cantidad)
VALUES
	('2022-05-03',5,9,7);

SELECT * FROM Venta ORDER BY id DESC LIMIT 1;

/* ============================================================================
8. Crear un TRIGGER que levante un error de SQL cuando queremos crear una venta con valores negativos en la cantidad
============================================================================= */
DROP TRIGGER IF EXISTS insert_venta_negativo;
DELIMITER $$
CREATE TRIGGER insert_venta_negativo BEFORE INSERT
	ON Venta
	FOR EACH ROW BEGIN
		IF NEW.cantidad < 1 THEN
			SIGNAL SQLSTATE '91239' SET MESSAGE_TEXT = 'No se pueden realizar ventas con cantidades negativas!';
        END IF;
	END$$
DELIMITER ;

INSERT INTO 
	Venta (fecha,id_empleado,id_publicacion,cantidad)
VALUES
	('2022-05-03',5,9,-10);