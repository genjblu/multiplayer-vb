// Frontend logic for Live Server Tracker (Bilingual: EN / RU)
const serversGrid = document.getElementById('servers-grid');
const loadingEl = document.getElementById('loading');
const emptyStateEl = document.getElementById('empty-state');
const statServers = document.getElementById('stat-servers');
const statPlayers = document.getElementById('stat-players');
const searchInput = document.getElementById('search-input');
const modeFilter = document.getElementById('mode-filter');
const refreshBtn = document.getElementById('refresh-btn');
const toast = document.getElementById('toast');
const btnLangEn = document.getElementById('lang-en');
const btnLangRu = document.getElementById('lang-ru');
const docTitle = document.getElementById('doc-title');

let allServers = [];
let currentLang = localStorage.getItem('master_tracker_lang') || (navigator.language && navigator.language.startsWith('ru') ? 'ru' : 'en');

const I18N = {
    en: {
        pageTitle: "Server Browser | Multiplayer FPS",
        serversOnline: "Servers Online:",
        playersOnline: "Players in Game:",
        searchPlaceholder: "Search by room name, host, map, or IP...",
        allModes: "All Modes",
        modeFFA: "FFA (Free For All)",
        mode2v2: "2v2 Teams",
        mode3v3v3: "3v3v3 Teams",
        mode4v4: "4v4 Teams",
        refresh: "Refresh",
        loading: "Loading active servers...",
        noServersTitle: "No active servers",
        noServersDesc: "No public servers online right now. Launch the game and host a room!",
        footerUpdate: "Master Server Tracker • Auto-refreshes every 3 seconds",
        footerHelp: "To join, copy the server IP:Port and paste it into Direct Connect in-game.",
        host: "Host:",
        map: "Map",
        mode: "Mode",
        players: "Players",
        friendlyFire: "Friendly Fire",
        ffOn: "On",
        ffOff: "Off",
        copyIP: "Copy IP",
        copiedToast: "IP copied to clipboard!",
        inGame: "IN GAME",
        inLobby: "IN LOBBY"
    },
    ru: {
        pageTitle: "Мониторинг серверов | Multiplayer FPS",
        serversOnline: "Серверов онлайн:",
        playersOnline: "Игроков в игре:",
        searchPlaceholder: "Поиск сервера по названию, хосту, карте или IP...",
        allModes: "Все режимы",
        modeFFA: "FFA (Каждый за себя)",
        mode2v2: "2v2 Команды",
        mode3v3v3: "3v3v3 Команды",
        mode4v4: "4v4 Команды",
        refresh: "Обновить",
        loading: "Загрузка активных серверов...",
        noServersTitle: "Нет активных серверов",
        noServersDesc: "Сейчас нет активных серверов. Запустите игру и создайте первую комнату!",
        footerUpdate: "Master Server Tracker • Автообновление каждые 3 секунды",
        footerHelp: "Для подключения скопируйте IP и вставьте в игре в разделе «Подключиться по IP».",
        host: "Хост:",
        map: "Карта",
        mode: "Режим",
        players: "Игроки",
        friendlyFire: "Огонь по своим",
        ffOn: "Вкл",
        ffOff: "Выкл",
        copyIP: "Копировать IP",
        copiedToast: "IP скопирован в буфер обмена!",
        inGame: "В ИГРЕ",
        inLobby: "В ЛОББИ"
    }
};

function setLanguage(lang) {
    currentLang = lang;
    localStorage.setItem('master_tracker_lang', lang);
    document.documentElement.lang = lang;

    const t = I18N[lang] || I18N.en;
    if (docTitle) docTitle.textContent = t.pageTitle;

    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        if (t[key]) el.textContent = t[key];
    });

    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        if (t[key]) el.placeholder = t[key];
    });

    if (btnLangEn && btnLangRu) {
        btnLangEn.classList.toggle('active', lang === 'en');
        btnLangRu.classList.toggle('active', lang === 'ru');
    }

    renderServers();
}

async function fetchServers() {
    try {
        const res = await fetch('/api/servers');
        if (!res.ok) throw new Error('Network error');
        const data = await res.json();
        allServers = data.servers || [];
        renderServers();
        updateStats();
    } catch (err) {
        console.error('Failed to fetch servers:', err);
    } finally {
        if (loadingEl) loadingEl.classList.add('hidden');
    }
}

function updateStats() {
    if (statServers) statServers.textContent = allServers.length;
    const totalPlayers = allServers.reduce((sum, s) => sum + (s.players || 0), 0);
    if (statPlayers) statPlayers.textContent = totalPlayers;
}

function renderServers() {
    const t = I18N[currentLang] || I18N.en;
    const query = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const mode = modeFilter ? modeFilter.value : 'all';

    const filtered = allServers.filter(s => {
        const matchesQuery = 
            (s.name && s.name.toLowerCase().includes(query)) ||
            (s.host_name && s.host_name.toLowerCase().includes(query)) ||
            (s.map && s.map.toLowerCase().includes(query)) ||
            (s.ip && s.ip.toLowerCase().includes(query));

        const matchesMode = (mode === 'all') || (s.mode === mode);
        return matchesQuery && matchesMode;
    });

    if (filtered.length === 0) {
        serversGrid.innerHTML = '';
        if (emptyStateEl) emptyStateEl.classList.remove('hidden');
        return;
    }

    if (emptyStateEl) emptyStateEl.classList.add('hidden');

    const modeLabels = {
        'ffa': t.modeFFA,
        '2v2': t.mode2v2,
        '3v3v3': t.mode3v3v3,
        '4v4': t.mode4v4
    };

    serversGrid.innerHTML = filtered.map(s => {
        const statusClass = s.in_game ? 'in-game' : 'in-lobby';
        const statusText = s.in_game ? t.inGame : t.inLobby;
        const fullAddress = `${s.ip}:${s.port}`;
        const modeText = modeLabels[s.mode] || s.mode;
        const ffText = s.friendly_fire ? t.ffOn : t.ffOff;

        return `
            <div class="server-card">
                <div class="card-header">
                    <div>
                        <div class="server-title">${escapeHtml(s.name)}</div>
                        <div class="server-host">${t.host} <strong>${escapeHtml(s.host_name)}</strong></div>
                    </div>
                    <span class="status-badge ${statusClass}">${statusText}</span>
                </div>

                <div class="card-details">
                    <div class="detail-item">
                        <span class="detail-label">${t.map}</span>
                        <span class="detail-val">${escapeHtml(s.map)}</span>
                    </div>
                    <div class="detail-item">
                        <span class="detail-label">${t.mode}</span>
                        <span class="detail-val">${escapeHtml(modeText)}</span>
                    </div>
                    <div class="detail-item">
                        <span class="detail-label">${t.players}</span>
                        <span class="detail-val">${s.players} / ${s.max_players}</span>
                    </div>
                    <div class="detail-item">
                        <span class="detail-label">${t.friendlyFire}</span>
                        <span class="detail-val">${ffText}</span>
                    </div>
                </div>

                <div class="card-footer">
                    <div class="ip-container">
                        <span>${fullAddress}</span>
                    </div>
                    <button class="btn-copy" type="button" onclick="copyToClipboard('${fullAddress}')">
                        ${t.copyIP}
                    </button>
                </div>
            </div>
        `;
    }).join('');
}

function copyToClipboard(text) {
    const t = I18N[currentLang] || I18N.en;
    navigator.clipboard.writeText(text).then(() => {
        showToast(t.copiedToast);
    }).catch(err => {
        console.error('Copy failed:', err);
    });
}

function showToast(msg) {
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.remove('hidden');
    setTimeout(() => {
        toast.classList.add('hidden');
    }, 2500);
}

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

// Event Listeners
if (searchInput) searchInput.addEventListener('input', renderServers);
if (modeFilter) modeFilter.addEventListener('change', renderServers);
if (refreshBtn) refreshBtn.addEventListener('click', () => {
    if (loadingEl) loadingEl.classList.remove('hidden');
    fetchServers();
});

if (btnLangEn) btnLangEn.addEventListener('click', () => setLanguage('en'));
if (btnLangRu) btnLangRu.addEventListener('click', () => setLanguage('ru'));

// Initialize language and data
setLanguage(currentLang);
fetchServers();
setInterval(fetchServers, 3000);
