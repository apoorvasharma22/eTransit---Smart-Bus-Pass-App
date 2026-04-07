<?php

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') exit(0);

//  DB Config
define('DB_HOST', 'localhost');
define('DB_NAME', 'etransit');
define('DB_USER', 'root');
define('DB_PASS', '');
define('JWT_SECRET', 'etransit_secret_key_change_in_production');

//  DB Connection 
function db(): PDO {
    static $pdo;
    if (!$pdo) {
        $pdo = new PDO(
            "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
            DB_USER, DB_PASS,
            [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
            ]
        );
    }
    return $pdo;
}

//  Simple JWT 
function jwt_sign(array $payload): string {
    $header  = base64_encode(json_encode(['alg'=>'HS256','typ'=>'JWT']));
    $payload = base64_encode(json_encode($payload));
    $sig     = base64_encode(hash_hmac('sha256', "$header.$payload", JWT_SECRET, true));
    return "$header.$payload.$sig";
}
function jwt_verify(string $token): ?array {
    [$header, $payload, $sig] = explode('.', $token) + [null,null,null];
    if (!$header || !$payload || !$sig) return null;
    $expected = base64_encode(hash_hmac('sha256', "$header.$payload", JWT_SECRET, true));
    if (!hash_equals($expected, $sig)) return null;
    $data = json_decode(base64_decode($payload), true);
    if ($data['exp'] < time()) return null;
    return $data;
}
function auth(): array {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/Bearer\s+(.+)/i', $h, $m)) respond(401,'Unauthorized');
    $payload = jwt_verify($m[1]);
    if (!$payload) respond(401,'Token invalid or expired');
    return $payload;
}

//  Helpers
function respond(int $code, $data): never {
    http_response_code($code);
    echo json_encode(['status' => $code < 400 ? 'success' : 'error', 'data' => $data]);
    exit;
}
function body(): array {
    return json_decode(file_get_contents('php://input'), true) ?? [];
}
function required(array $data, array $keys): void {
    foreach ($keys as $k) {
        if (empty($data[$k])) respond(422, "Field '$k' is required");
    }
}

//  ROUTER
$method = $_SERVER['REQUEST_METHOD'];
$path   = trim($_SERVER['PATH_INFO'] ?? parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH), '/');
$parts  = explode('/', $path);
$resource = $parts[1] ?? '';  
$id       = $parts[2] ?? null;

match("$method:$resource") {
    //AUTh
    'POST:register'  => register(),
    'POST:login'     => login(),

    //USER
    'GET:profile'    => getProfile(),
    'PUT:profile'    => updateProfile(),

    //PASSES
    'GET:passes'     => getPasses(),
    'POST:passes'    => purchasePass(),
    'GET:balance'    => getBalance(),

    //TOPUP
    'POST:topup'     => topUp(),
    'GET:topup'      => getTopupHistory(),

    //TRIPS 
    'GET:trips'      => getTrips(),
    'POST:tap-in'    => tapIn(),
    'POST:tap-out'   => tapOut(),

    //ROUTES 
    'GET:routes'     => getRoutes(),

    //NOTIFICATIONS 
    'GET:notifications'  => getNotifications(),
    'PUT:notifications'  => markRead(),

    //PASS TYPES 
    'GET:pass-types' => getPassTypes(),

    default          => respond(404, 'Endpoint not found'),
};

//  ENDPOINT HANDLERS

// AUTH
function register(): never {
    $b = body();
    required($b, ['name','email','phone','password']);
    $pdo = db();

    $exists = $pdo->prepare("SELECT id FROM users WHERE email=? OR phone=?");
    $exists->execute([$b['email'], $b['phone']]);
    if ($exists->fetch()) respond(409, 'Email or phone already registered');

    $hash = password_hash($b['password'], PASSWORD_BCRYPT);
    $stmt = $pdo->prepare("INSERT INTO users (name,email,phone,password_hash) VALUES (?,?,?,?)");
    $stmt->execute([$b['name'], $b['email'], $b['phone'], $hash]);
    $userId = $pdo->lastInsertId();

    // Auto-create a basic pass
    $passNum = strtoupper(sprintf('%04d-%04d-%04d-%04d',
        rand(1000,9999), rand(1000,9999), rand(1000,9999), rand(1000,9999)));
    $qr   = bin2hex(random_bytes(16));
    $stmt = $pdo->prepare("INSERT INTO bus_passes (user_id,pass_type_id,pass_number,balance,issue_date,expiry_date,qr_token) VALUES (?,?,?,?,CURDATE(),DATE_ADD(CURDATE(),INTERVAL 30 DAY),?)");
    $stmt->execute([$userId, 1, $passNum, 0, $qr]);

    respond(201, ['user_id' => $userId, 'pass_number' => $passNum]);
}

function login(): never {
    $b = body();
    required($b, ['email','password']);

    $stmt = db()->prepare("SELECT id,name,email,password_hash,role FROM users WHERE email=? AND is_active=1");
    $stmt->execute([$b['email']]);
    $user = $stmt->fetch();

    if (!$user || !password_verify($b['password'], $user['password_hash']))
        respond(401, 'Invalid email or password');

    $token = jwt_sign([
        'sub'  => $user['id'],
        'name' => $user['name'],
        'role' => $user['role'],
        'exp'  => time() + 86400 * 7,
    ]);
    unset($user['password_hash']);
    respond(200, ['token' => $token, 'user' => $user]);
}

//PROFILE

function getProfile(): never {
    $u = auth();
    $stmt = db()->prepare("SELECT id,name,email,phone,profile_pic,role,created_at FROM users WHERE id=?");
    $stmt->execute([$u['sub']]);
    respond(200, $stmt->fetch());
}

function updateProfile(): never {
    $u = auth(); $b = body();
    $allowed = ['name','phone','profile_pic'];
    $sets = []; $vals = [];
    foreach ($allowed as $k) {
        if (isset($b[$k])) { $sets[] = "$k=?"; $vals[] = $b[$k]; }
    }
    if (!$sets) respond(400, 'Nothing to update');
    $vals[] = $u['sub'];
    db()->prepare("UPDATE users SET " . implode(',',$sets) . " WHERE id=?")->execute($vals);
    respond(200, 'Profile updated');
}

// PASSES

function getPasses(): never {
    $u = auth();
    $stmt = db()->prepare("
        SELECT bp.*, pt.name AS pass_type_name, pt.duration_days
        FROM bus_passes bp
        JOIN pass_types pt ON pt.id = bp.pass_type_id
        WHERE bp.user_id = ? ORDER BY bp.id DESC
    ");
    $stmt->execute([$u['sub']]);
    respond(200, $stmt->fetchAll());
}

function purchasePass(): never {
    $u = auth(); $b = body();
    required($b, ['pass_type_id']);
    $pdo = db();

    $pt = $pdo->prepare("SELECT * FROM pass_types WHERE id=? AND is_active=1");
    $pt->execute([$b['pass_type_id']]);
    $type = $pt->fetch();
    if (!$type) respond(404, 'Pass type not found');

    $passNum = strtoupper(sprintf('%04d-%04d-%04d-%04d',
        rand(1000,9999), rand(1000,9999), rand(1000,9999), rand(1000,9999)));

    $stmt = $pdo->prepare("
        INSERT INTO bus_passes (user_id,pass_type_id,pass_number,balance,issue_date,expiry_date,qr_token)
        VALUES (?,?,?,?,CURDATE(),DATE_ADD(CURDATE(),INTERVAL ? DAY),?)
    ");
    $stmt->execute([$u['sub'], $type['id'], $passNum, 0, $type['duration_days'], bin2hex(random_bytes(16))]);
    respond(201, ['pass_number' => $passNum, 'expires_in_days' => $type['duration_days']]);
}

function getBalance(): never {
    $u = auth();
    $stmt = db()->prepare("SELECT pass_number, balance, tier, expiry_date FROM bus_passes WHERE user_id=? AND is_active=1 ORDER BY id DESC LIMIT 1");
    $stmt->execute([$u['sub']]);
    respond(200, $stmt->fetch());
}

//TOPUP 
function topUp(): never {
    $u = auth(); $b = body();
    required($b, ['amount','payment_method']);

    $amount = floatval($b['amount']);
    if ($amount <= 0 || $amount > 10000) respond(400, 'Amount must be between ₹1 and ₹10000');

    $pdo  = db();
    $pass = $pdo->prepare("SELECT id, balance FROM bus_passes WHERE user_id=? AND is_active=1 ORDER BY id DESC LIMIT 1");
    $pass->execute([$u['sub']]);
    $p = $pass->fetch();
    if (!$p) respond(404, 'No active pass found');

    $txnRef = 'TOP' . date('YmdHis') . rand(10,99);

    $pdo->beginTransaction();
    $pdo->prepare("UPDATE bus_passes SET balance = balance + ? WHERE id=?")->execute([$amount, $p['id']]);
    $pdo->prepare("INSERT INTO topup_transactions (txn_ref,pass_id,user_id,amount,payment_method,status,balance_before,balance_after,completed_at) VALUES (?,?,?,?,?,'success',?,?,NOW())")
        ->execute([$txnRef, $p['id'], $u['sub'], $amount, $b['payment_method'], $p['balance'], $p['balance'] + $amount]);
    $pdo->commit();

    respond(200, ['txn_ref' => $txnRef, 'new_balance' => $p['balance'] + $amount]);
}

function getTopupHistory(): never {
    $u = auth();
    $stmt = db()->prepare("SELECT * FROM topup_transactions WHERE user_id=? ORDER BY initiated_at DESC LIMIT 20");
    $stmt->execute([$u['sub']]);
    respond(200, $stmt->fetchAll());
}

// TRIPS

function getTrips(): never {
    $u = auth();
    $limit  = intval($_GET['limit']  ?? 20);
    $status = $_GET['status'] ?? null;
    $sql = "SELECT t.*, r.route_number, r.route_name FROM trips t JOIN routes r ON r.id=t.route_id WHERE t.user_id=?";
    $params = [$u['sub']];
    if ($status) { $sql .= " AND t.status=?"; $params[] = $status; }
    $sql .= " ORDER BY t.tap_in_time DESC LIMIT ?";
    $params[] = $limit;
    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    respond(200, $stmt->fetchAll());
}

function tapIn(): never {
    $u = auth(); $b = body();
    required($b, ['pass_number','route_id']);

    $pdo = db();
    // Get route fare
    $route = $pdo->prepare("SELECT base_fare FROM routes WHERE id=? AND is_active=1");
    $route->execute([$b['route_id']]);
    $r = $route->fetch();
    if (!$r) respond(404, 'Route not found');

    $result = $txnId = null;
    $pdo->prepare("CALL sp_tap_in(?,?,?,@result,@txn);")->execute([$b['pass_number'],$b['route_id'],$r['base_fare']]);
    $out = $pdo->query("SELECT @result AS result, @txn AS txn")->fetch();

    match ($out['result']) {
        'SUCCESS'               => respond(200, ['txn_id' => $out['txn'], 'fare' => $r['base_fare']]),
        'PASS_NOT_FOUND'        => respond(404, 'Pass not found'),
        'PASS_EXPIRED'          => respond(403, 'Pass has expired'),
        'INSUFFICIENT_BALANCE'  => respond(402, 'Insufficient balance'),
        default                 => respond(500, 'Unknown error'),
    };
}

function tapOut(): never {
    $u = auth(); $b = body();
    required($b, ['txn_id']);

    $stmt = db()->prepare("UPDATE trips SET status='completed', tap_out_time=NOW() WHERE txn_id=? AND user_id=? AND status='active'");
    $stmt->execute([$b['txn_id'], $u['sub']]);
    respond($stmt->rowCount() ? 200 : 404, $stmt->rowCount() ? 'Trip completed' : 'Trip not found or already closed');
}

// ROUTES

function getRoutes(): never {
    $search = $_GET['q'] ?? null;
    $sql = "SELECT * FROM routes WHERE is_active=1";
    $params = [];
    if ($search) {
        $sql .= " AND (route_number LIKE ? OR route_name LIKE ? OR origin LIKE ? OR destination LIKE ?)";
        $like = "%$search%";
        $params = [$like,$like,$like,$like];
    }
    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    respond(200, $stmt->fetchAll());
}

//NOTIFICATIONS

function getNotifications(): never {
    $u = auth();
    $stmt = db()->prepare("SELECT * FROM notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 20");
    $stmt->execute([$u['sub']]);
    respond(200, $stmt->fetchAll());
}

function markRead(): never {
    $u = auth();
    db()->prepare("UPDATE notifications SET is_read=1 WHERE user_id=?")->execute([$u['sub']]);
    respond(200, 'All notifications marked as read');
}

//PASS TYPES 

function getPassTypes(): never {
    $stmt = db()->query("SELECT * FROM pass_types WHERE is_active=1 ORDER BY price");
    respond(200, $stmt->fetchAll());
}