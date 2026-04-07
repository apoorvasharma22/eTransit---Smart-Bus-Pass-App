CREATE DATABASE IF NOT EXISTS etransit CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE etransit;

--  1. USERS
CREATE TABLE users (
    id              INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL,
    email           VARCHAR(150)    UNIQUE NOT NULL,
    phone           VARCHAR(15)     UNIQUE NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    profile_pic     VARCHAR(255)    DEFAULT NULL,
    role            ENUM('user','admin') DEFAULT 'user',
    is_active       TINYINT(1)      DEFAULT 1,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;


--  2. PASS TYPES
CREATE TABLE pass_types (
    id              INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(50)     NOT NULL,           
    price           DECIMAL(8,2)    NOT NULL,
    duration_days   INT             NOT NULL,
    max_rides       INT             DEFAULT NULL,       
    description     TEXT,
    is_active       TINYINT(1)      DEFAULT 1,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO pass_types (name, price, duration_days, max_rides, description) VALUES
('Single Ride',  26.00,   1,  1,     'Single trip at standard fare'),
('Daily Pass',   40.00,   1,  NULL,  '24-hour unlimited travel pass'),
('Weekly Pass',  200.00,  7,  NULL,  '7-day unlimited travel pass'),
('Monthly Pass', 699.00,  30, NULL,  '30-day unlimited travel — most popular'),
('Annual Pass',  6999.00, 365,NULL,  '365-day unlimited travel — best value');

--  3. BUS PASSES 
CREATE TABLE bus_passes (
    id              INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    user_id         INT UNSIGNED    NOT NULL,
    pass_type_id    INT UNSIGNED    NOT NULL,
    pass_number     VARCHAR(20)     UNIQUE NOT NULL,    
    tier            ENUM('Standard','Silver','Gold','Platinum') DEFAULT 'Standard',
    balance         DECIMAL(10,2)   DEFAULT 0.00,
    issue_date      DATE            NOT NULL,
    expiry_date     DATE            NOT NULL,
    is_active       TINYINT(1)      DEFAULT 1,
    rides_used      INT             DEFAULT 0,
    loyalty_points  INT             DEFAULT 0,
    qr_token        VARCHAR(255)    UNIQUE,
    nfc_uid         VARCHAR(50)     UNIQUE DEFAULT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id)      REFERENCES users(id)      ON DELETE CASCADE,
    FOREIGN KEY (pass_type_id) REFERENCES pass_types(id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--  4. ROUTES
CREATE TABLE routes (
    id              INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    route_number    VARCHAR(10)     UNIQUE NOT NULL,
    route_name      VARCHAR(100)    NOT NULL,
    origin          VARCHAR(100)    NOT NULL,
    destination     VARCHAR(100)    NOT NULL,
    via             VARCHAR(255)    DEFAULT NULL,
    total_stops     INT             DEFAULT 0,
    distance_km     DECIMAL(6,2)    DEFAULT NULL,
    base_fare       DECIMAL(6,2)    NOT NULL,
    frequency_min   INT             DEFAULT NULL,      
    is_ac           TINYINT(1)      DEFAULT 0,
    is_active       TINYINT(1)      DEFAULT 1,
    first_bus       TIME            DEFAULT '05:30:00',
    last_bus        TIME            DEFAULT '22:30:00',
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO routes (route_number, route_name, origin, destination, total_stops, distance_km, base_fare, frequency_min, is_ac, is_active) VALUES
('42',  'Central Corridor',  'Sector 17',      'ISBT',              14, 18.5, 26.00, 8,  1, 1),
('18',  'Railway Express',   'Railway Station', 'Sector 35',        9,  12.0, 18.00, 12, 0, 1),
('7C',  'Hospital Link',     'Sector 43',       'PGI Hospital',     11, 14.2, 22.00, 10, 1, 1),
('22',  'IT Park Shuttle',   'IT Park',         'Sector 17',        8,  10.0, 20.00, 15, 1, 1),
('11',  'City Loop',         'Sector 11',       'Chandigarh Stn',   6,  8.0,  14.00, 20, 0, 1),
('55',  'Mohali Link',       'Mohali Chowk',    'PGI Hospital',     16, 22.0, 32.00, 25, 0, 0),
('33',  'University Line',   'Panjab Uni',      'Sector 17',        7,  9.5,  16.00, 18, 0, 1),
('99',  'Airport Express',   'ISBT',            'Chandigarh Airport',5, 30.0, 55.00, 30, 1, 1),
('6A',  'Night Owl',         'ISBT',            'Sector 46',        12, 16.0, 24.00, 45, 0, 0);

--  5. STOPS
CREATE TABLE stops (
    id          INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    stop_name   VARCHAR(100)    NOT NULL,
    stop_code   VARCHAR(10)     UNIQUE NOT NULL,
    latitude    DECIMAL(9,6)    DEFAULT NULL,
    longitude   DECIMAL(9,6)   DEFAULT NULL,
    is_major    TINYINT(1)      DEFAULT 0,
    is_active   TINYINT(1)      DEFAULT 1
) ENGINE=InnoDB;

--  6. ROUTE STOPS (many-to-many)
CREATE TABLE route_stops (
    id              INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    route_id        INT UNSIGNED    NOT NULL,
    stop_id         INT UNSIGNED    NOT NULL,
    stop_order      INT             NOT NULL,
    distance_from_origin DECIMAL(6,2) DEFAULT 0.00,
    fare_from_origin     DECIMAL(6,2) DEFAULT 0.00,

    FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE CASCADE,
    FOREIGN KEY (stop_id)  REFERENCES stops(id)  ON DELETE CASCADE,
    UNIQUE KEY uq_route_stop (route_id, stop_order)
) ENGINE=InnoDB;

--  7. BUSES (fleet)
CREATE TABLE buses (
    id              INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    bus_number      VARCHAR(20)     UNIQUE NOT NULL,
    route_id        INT UNSIGNED    DEFAULT NULL,
    capacity        INT             DEFAULT 50,
    bus_type        ENUM('Standard','AC','Electric','Minibus') DEFAULT 'Standard',
    current_lat     DECIMAL(9,6)    DEFAULT NULL,
    current_lng     DECIMAL(9,6)    DEFAULT NULL,
    current_stop_id INT UNSIGNED    DEFAULT NULL,
    seats_available INT             DEFAULT 50,
    status          ENUM('active','idle','maintenance','breakdown') DEFAULT 'idle',
    last_updated    TIMESTAMP       DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE SET NULL,
    FOREIGN KEY (current_stop_id) REFERENCES stops(id) ON DELETE SET NULL
) ENGINE=InnoDB;

--  8. TRIPS 
CREATE TABLE trips (
    id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    txn_id          VARCHAR(20)     UNIQUE NOT NULL,    
    pass_id         INT UNSIGNED    NOT NULL,
    user_id         INT UNSIGNED    NOT NULL,
    route_id        INT UNSIGNED    NOT NULL,
    bus_id          INT UNSIGNED    DEFAULT NULL,
    board_stop_id   INT UNSIGNED    DEFAULT NULL,
    alight_stop_id  INT UNSIGNED    DEFAULT NULL,
    fare_charged    DECIMAL(8,2)    DEFAULT 0.00,
    tap_in_time     DATETIME        NOT NULL,
    tap_out_time    DATETIME        DEFAULT NULL,
    status          ENUM('active','completed','pending','failed','refunded') DEFAULT 'pending',
    payment_method  ENUM('pass','balance','cash','upi') DEFAULT 'pass',
    loyalty_earned  INT             DEFAULT 0,
    notes           VARCHAR(255)    DEFAULT NULL,
    created_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (pass_id)         REFERENCES bus_passes(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)         REFERENCES users(id)      ON DELETE CASCADE,
    FOREIGN KEY (route_id)        REFERENCES routes(id)     ON DELETE RESTRICT,
    FOREIGN KEY (bus_id)          REFERENCES buses(id)      ON DELETE SET NULL,
    FOREIGN KEY (board_stop_id)   REFERENCES stops(id)      ON DELETE SET NULL,
    FOREIGN KEY (alight_stop_id)  REFERENCES stops(id)      ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_pass_id (pass_id),
    INDEX idx_tap_in (tap_in_time),
    INDEX idx_status (status)
) ENGINE=InnoDB;

--  9. TOPUP TRANSACTIONS
CREATE TABLE topup_transactions (
    id                  INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    txn_ref             VARCHAR(30)     UNIQUE NOT NULL,
    pass_id             INT UNSIGNED    NOT NULL,
    user_id             INT UNSIGNED    NOT NULL,
    amount              DECIMAL(10,2)   NOT NULL,
    payment_method      ENUM('upi','card','netbanking','wallet','cash') NOT NULL,
    payment_gateway     VARCHAR(50)     DEFAULT NULL,
    gateway_txn_id      VARCHAR(100)    DEFAULT NULL,
    status              ENUM('initiated','success','failed','refunded') DEFAULT 'initiated',
    balance_before      DECIMAL(10,2)   NOT NULL,
    balance_after       DECIMAL(10,2)   DEFAULT NULL,
    initiated_at        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    completed_at        TIMESTAMP       DEFAULT NULL,

    FOREIGN KEY (pass_id)  REFERENCES bus_passes(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)  REFERENCES users(id)      ON DELETE CASCADE
) ENGINE=InnoDB;

--  10. NOTIFICATIONS
CREATE TABLE notifications (
    id          INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    user_id     INT UNSIGNED    NOT NULL,
    title       VARCHAR(100)    NOT NULL,
    message     TEXT            NOT NULL,
    type        ENUM('info','alert','promo','system') DEFAULT 'info',
    is_read     TINYINT(1)      DEFAULT 0,
    created_at  TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_unread (user_id, is_read)
) ENGINE=InnoDB;

--  11. FEEDBACK
CREATE TABLE feedback (
    id          INT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    user_id     INT UNSIGNED    NOT NULL,
    trip_id     BIGINT UNSIGNED DEFAULT NULL,
    route_id    INT UNSIGNED    DEFAULT NULL,
    rating      TINYINT         CHECK(rating BETWEEN 1 AND 5),
    comment     TEXT            DEFAULT NULL,
    created_at  TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id)  REFERENCES users(id)  ON DELETE CASCADE,
    FOREIGN KEY (trip_id)  REFERENCES trips(id)  ON DELETE SET NULL,
    FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE SET NULL
) ENGINE=InnoDB;

--  12. ADMIN ACTIVITY LOG
CREATE TABLE activity_log (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     INT UNSIGNED    DEFAULT NULL,
    action      VARCHAR(100)    NOT NULL,
    entity_type VARCHAR(50)     DEFAULT NULL,
    entity_id   INT UNSIGNED    DEFAULT NULL,
    details     JSON            DEFAULT NULL,
    ip_address  VARCHAR(45)     DEFAULT NULL,
    created_at  TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_user_action (user_id, action),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

--  SAMPLE DATA

-- Users
INSERT INTO users (name, email, phone, password_hash, role) VALUES
('Apoorva Sharma',   'apoorvasharma2023@gmail.com',  '+918059752501', '$2y$12$hashedpassword1', 'user'),
('Priya Sharma',  'priya@example.com',  '+919876543211', '$2y$12$hashedpassword2', 'user'),
('Admin User',    'admin@etransit.in',  '+919876543212', '$2y$12$hashedpassword3', 'admin');

-- Bus Pass
INSERT INTO bus_passes (user_id, pass_type_id, pass_number, tier, balance, issue_date, expiry_date, loyalty_points, qr_token) VALUES
(1, 4, '4217-5893-6401-8891', 'Gold',     847.50, '2026-03-01', '2026-03-31', 2340, UUID()),
(2, 2, '9830-2214-7752-3301', 'Standard',  40.00, '2026-02-21', '2026-02-22', 120,  UUID());

-- Sample trips
INSERT INTO trips (txn_id, pass_id, user_id, route_id, fare_charged, tap_in_time, tap_out_time, status, loyalty_earned) VALUES
('TXN001', 1, 1, 1, 26.00, '2026-02-21 09:15:00', '2026-02-21 09:48:00', 'completed', 5),
('TXN002', 1, 1, 2, 18.00, '2026-02-21 07:45:00', '2026-02-21 08:10:00', 'completed', 3),
('TXN003', 1, 1, 3, 22.00, '2026-02-20 18:10:00', '2026-02-20 18:45:00', 'completed', 4),
('TXN004', 1, 1, 4, 20.00, '2026-02-20 14:30:00', NULL,                  'pending',   0),
('TXN005', 1, 1, 1, 26.00, '2026-02-19 08:00:00', NULL,                  'failed',    0);

--  USEFUL VIEWS

-- Active passes with user info
CREATE OR REPLACE VIEW v_active_passes AS
SELECT
    bp.id, bp.pass_number, bp.tier, bp.balance,
    bp.issue_date, bp.expiry_date, bp.rides_used, bp.loyalty_points,
    u.name AS user_name, u.email, u.phone,
    pt.name AS pass_type_name, pt.price AS pass_price
FROM bus_passes bp
JOIN users u      ON u.id = bp.user_id
JOIN pass_types pt ON pt.id = bp.pass_type_id
WHERE bp.is_active = 1 AND bp.expiry_date >= CURDATE();

-- Monthly spending summary
CREATE OR REPLACE VIEW v_monthly_spending AS
SELECT
    user_id,
    YEAR(tap_in_time)  AS yr,
    MONTH(tap_in_time) AS mo,
    COUNT(*) AS total_trips,
    SUM(fare_charged)  AS total_spent
FROM trips
WHERE status = 'completed'
GROUP BY user_id, YEAR(tap_in_time), MONTH(tap_in_time);

--  STORED PROCEDURE: Tap-in (deduct fare)
DELIMITER $$
CREATE PROCEDURE sp_tap_in(
    IN  p_pass_number  VARCHAR(20),
    IN  p_route_id     INT,
    IN  p_fare         DECIMAL(8,2),
    OUT p_result       VARCHAR(50),
    OUT p_txn_id       VARCHAR(20)
)
BEGIN
    DECLARE v_pass_id     INT;
    DECLARE v_user_id     INT;
    DECLARE v_balance     DECIMAL(10,2);
    DECLARE v_expiry      DATE;
    DECLARE v_is_active   TINYINT;

    -- Lock the pass row
    SELECT id, user_id, balance, expiry_date, is_active
    INTO   v_pass_id, v_user_id, v_balance, v_expiry, v_is_active
    FROM   bus_passes
    WHERE  pass_number = p_pass_number
    FOR UPDATE;

    -- Validation
    IF v_pass_id IS NULL THEN
        SET p_result = 'PASS_NOT_FOUND'; LEAVE;
    END IF;
    IF v_is_active = 0 OR v_expiry < CURDATE() THEN
        SET p_result = 'PASS_EXPIRED'; LEAVE;
    END IF;
    IF v_balance < p_fare THEN
        SET p_result = 'INSUFFICIENT_BALANCE'; LEAVE;
    END IF;

    -- Generate txn id
    SET p_txn_id = CONCAT('TXN', DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'),
                   FLOOR(RAND() * 100));

    START TRANSACTION;
        -- Deduct balance
        UPDATE bus_passes SET balance = balance - p_fare, rides_used = rides_used + 1
        WHERE id = v_pass_id;
        -- Insert trip
        INSERT INTO trips (txn_id, pass_id, user_id, route_id, fare_charged, tap_in_time, status, loyalty_earned)
        VALUES (p_txn_id, v_pass_id, v_user_id, p_route_id, p_fare, NOW(), 'active',
                FLOOR(p_fare / 5));
    COMMIT;
    SET p_result = 'SUCCESS';
END$$
DELIMITER ;

--  STORED PROCEDURE: Top-up balance
DELIMITER $$
CREATE PROCEDURE sp_topup(
    IN  p_pass_number  VARCHAR(20),
    IN  p_amount       DECIMAL(10,2),
    IN  p_method       VARCHAR(20),
    OUT p_result       VARCHAR(50),
    OUT p_txn_ref      VARCHAR(30)
)
BEGIN
    DECLARE v_pass_id   INT;
    DECLARE v_user_id   INT;
    DECLARE v_balance   DECIMAL(10,2);

    SELECT id, user_id, balance INTO v_pass_id, v_user_id, v_balance
    FROM bus_passes WHERE pass_number = p_pass_number FOR UPDATE;

    IF v_pass_id IS NULL THEN
        SET p_result = 'PASS_NOT_FOUND'; LEAVE;
    END IF;
    IF p_amount <= 0 OR p_amount > 10000 THEN
        SET p_result = 'INVALID_AMOUNT'; LEAVE;
    END IF;

    SET p_txn_ref = CONCAT('TOP', DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'));

    START TRANSACTION;
        UPDATE bus_passes SET balance = balance + p_amount WHERE id = v_pass_id;
        INSERT INTO topup_transactions
            (txn_ref, pass_id, user_id, amount, payment_method, status, balance_before, balance_after, completed_at)
        VALUES
            (p_txn_ref, v_pass_id, v_user_id, p_amount, p_method, 'success', v_balance, v_balance + p_amount, NOW());
    COMMIT;
    SET p_result = 'SUCCESS';
END$$
DELIMITER ;
