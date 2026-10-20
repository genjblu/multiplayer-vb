const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Store active servers in memory:
// id -> { id, name, host_name, ip, port, map, mode, players, max_players, in_game, friendly_fire, last_heartbeat }
const servers = new Map();
const HEARTBEAT_TIMEOUT_MS = 20000; // 20 seconds timeout

// Helper to extract client IP
function getClientIp(req) {
    const forwarded = req.headers['x-forwarded-for'];
    if (forwarded) {
        return forwarded.split(',')[0].trim();
    }
    let ip = req.socket.remoteAddress || '';
    if (ip.startsWith('::ffff:')) {
        ip = ip.substring(7);
    }
    return ip;
}

// Clean up dead servers every 5 seconds
setInterval(() => {
    const now = Date.now();
    for (const [id, s] of servers.entries()) {
        if (now - s.last_heartbeat > HEARTBEAT_TIMEOUT_MS) {
            console.log(`[MasterServer] Server timed out: ${s.name} (${id})`);
            servers.delete(id);
        }
    }
}, 5000);

// --- REST API for Godot & Web ---

// 1. Get all active public servers
app.get('/api/servers', (req, res) => {
    const list = Array.from(servers.values())
        .filter(s => !s.is_private)
        .map(s => ({
            id: s.id,
            name: s.name,
            host_name: s.host_name,
            ip: s.ip,
            port: s.port,
            map: s.map,
            map_id: s.map_id || (s.map === 'MAP_INDUSTRIAL' || s.map === 'Industrial' ? 'Industrial' : 'default_arena'),
            mode: s.mode,
            players: s.players,
            max_players: s.max_players,
            in_game: s.in_game,
            friendly_fire: s.friendly_fire,
            room_code: s.room_code,
            uptime_seconds: Math.floor((Date.now() - s.created_at) / 1000)
        }));
    res.json({ servers: list, count: list.length });
});

// Helper to generate a unique 4-digit room code
function generateRoomCode() {
    let code = '';
    for (let attempts = 0; attempts < 100; attempts++) {
        code = Math.floor(1000 + Math.random() * 9000).toString();
        let exists = false;
        for (const s of servers.values()) {
            if (s.room_code === code) {
                exists = true;
                break;
            }
        }
        if (!exists) return code;
    }
    return Math.floor(10000 + Math.random() * 90000).toString();
}

// 2. Register a new server (called by Godot host)
app.post('/api/servers/register', (req, res) => {
    const { name, host_name, port, map, map_id, mode, players, max_players, friendly_fire, custom_ip, is_private, room_code } = req.body;
    
    // Auto-detect public IP or accept explicit custom_ip
    let detectedIp = custom_ip && custom_ip.trim() !== '' ? custom_ip.trim() : getClientIp(req);
    let serverPort = parseInt(port) || 7777;

    // Handle tunnel host:port format (e.g. playit.gg:12345 or 147.185.x.x:12345)
    if (detectedIp.includes(':')) {
        const parts = detectedIp.split(':');
        detectedIp = parts[0].trim();
        if (parts[1]) {
            serverPort = parseInt(parts[1]) || serverPort;
        }
    }

    const serverId = `${detectedIp}:${serverPort}`;
    const finalRoomCode = (room_code && room_code.trim() !== '') ? room_code.trim().toUpperCase() : generateRoomCode();

    const serverData = {
        id: serverId,
        room_code: finalRoomCode,
        is_private: Boolean(is_private),
        name: (name || 'Игровой сервер').substring(0, 32),
        host_name: (host_name || 'Хост').substring(0, 16),
        ip: detectedIp,
        port: serverPort,
        map: map || 'Industrial',
        map_id: map_id || (map === 'MAP_INDUSTRIAL' || map === 'Industrial' ? 'Industrial' : 'default_arena'),
        mode: mode || 'ffa',
        players: parseInt(players) || 1,
        max_players: parseInt(max_players) || 16,
        in_game: false,
        friendly_fire: Boolean(friendly_fire),
        created_at: Date.now(),
        last_heartbeat: Date.now()
    };

    servers.set(serverId, serverData);
    console.log(`[MasterServer] Registered: ${serverData.name} (Code: ${finalRoomCode}, Private: ${serverData.is_private}) at ${serverId}`);
    res.json({ success: true, server_id: serverId, room_code: finalRoomCode, public_ip: detectedIp });
});

// 2.5 Lookup room by code (for private or direct join)
app.get('/api/rooms/:code', (req, res) => {
    const searchCode = (req.params.code || '').trim().toUpperCase();
    if (!searchCode) {
        return res.status(400).json({ success: false, error: 'Код комнаты не указан' });
    }

    for (const s of servers.values()) {
        if (s.room_code && s.room_code.toUpperCase() === searchCode) {
            return res.json({
                success: true,
                server: {
                    id: s.id,
                    room_code: s.room_code,
                    name: s.name,
                    host_name: s.host_name,
                    ip: s.ip,
                    port: s.port,
                    map: s.map,
                    map_id: s.map_id,
                    mode: s.mode,
                    players: s.players,
                    max_players: s.max_players,
                    in_game: s.in_game,
                    friendly_fire: s.friendly_fire
                }
            });
        }
    }

    res.status(404).json({ success: false, error: 'Комната с таким кодом не найдена или неактивна' });
});

// 3. Heartbeat (called by Godot host every 5-10s)
app.post('/api/servers/heartbeat', (req, res) => {
    const { server_id, players, in_game, map, mode } = req.body;
    if (!server_id || !servers.has(server_id)) {
        return res.status(404).json({ success: false, error: 'Server not found' });
    }

    const s = servers.get(server_id);
    s.last_heartbeat = Date.now();
    if (players !== undefined) s.players = parseInt(players) || s.players;
    if (in_game !== undefined) s.in_game = Boolean(in_game);
    if (map) s.map = map;
    if (mode) s.mode = mode;

    res.json({ success: true });
});

// 4. Unregister (called on exit)
app.post('/api/servers/unregister', (req, res) => {
    const { server_id } = req.body;
    if (server_id && servers.has(server_id)) {
        servers.delete(server_id);
        console.log(`[MasterServer] Unregistered: ${server_id}`);
    }
    res.json({ success: true });
});

// 5. Global statistics
app.get('/api/stats', (req, res) => {
    let totalPlayers = 0;
    for (const s of servers.values()) {
        totalPlayers += s.players;
    }
    res.json({
        active_servers: servers.size,
        total_players: totalPlayers
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`=== Godot Master Server & Web Tracker running on http://0.0.0.0:${PORT} ===`);
});
