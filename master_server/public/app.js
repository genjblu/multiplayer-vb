// Frontend logic for Live Server Tracker
const serversGrid = document.getElementById('servers-grid');
const loadingEl = document.getElementById('loading');
const emptyStateEl = document.getElementById('empty-state');
const statServers = document.getElementById('stat-servers');
const statPlayers = document.getElementById('stat-players');
const searchInput = document.getElementById('search-input');
const modeFilter = document.getElementById('mode-filter');
const refreshBtn = document.getElementById('refresh-btn');
const toast = document.getElementById('toast');

let allServers = [];

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
        loadingEl.classList.add('hidden');
    }
}

function updateStats() {
    statServers.textContent = allServers.length;
    const totalPlayers = allServers.reduce((sum, s) => sum + (s.players || 0), 0);
    statPlayers.textContent = totalPlayers;
}

function renderServers() {
    const query = searchInput.value.toLowerCase().trim();
    const mode = modeFilter.value;

    const filtered = allServers.filter(s => {
        const matchesQuery = 
            s.name.toLowerCase().includes(query) ||
            s.host_name.toLowerCase().includes(query) ||
            s.map.toLowerCase().includes(query) ||
            s.ip.toLowerCase().includes(query);

        const matchesMode = (mode === 'all') || (s.mode === mode);
        return matchesQuery && matchesMode;
    });

    if (filtered.length === 0) {
        serversGrid.innerHTML = '';
        emptyStateEl.classList.remove('hidden');
        return;
    }

    emptyStateEl.classList.add('hidden');

    const modeLabels = {
        'ffa': 'FFA (Каждый за себя)',
        '2v2': '2v2 Команды',
        '3v3v3': '3v3v3',
        '4v4': '4v4'
    };

    serversGrid.innerHTML = filtered.map(s => {
        const statusClass = s.in_game ? 'in-game' : 'in-lobby';
        const statusText = s.in_game ? 'В ИГРЕ' : 'В ЛОББИ';
        const fullAddress = `${s.ip}:${s.port}`;
        const modeText = modeLabels[s.mode] || s.mode;
        const ffText = s.friendly_fire ? 'Вкл' : 'Выкл';

        return `
            <div class="server-card">
                <div class="card-header">
                    <div>
                        <div class="server-title">${escapeHtml(s.name)}</div>
                        <div class="server-host">Хост: <strong>${escapeHtml(s.host_name)}</strong></div>
                    </div>
                    <span class="status-badge ${statusClass}">${statusText}</span>
                </div>

                <div class="card-details">
                    <div class="detail-item">
                        <span class="detail-label">Карта</span>
                        <span class="detail-val">🗺️ ${escapeHtml(s.map)}</span>
                    </div>
                    <div class="detail-item">
                        <span class="detail-label">Режим</span>
                        <span class="detail-val">⚔️ ${escapeHtml(modeText)}</span>
                    </div>
                    <div class="detail-item">
                        <span class="detail-label">Игроки</span>
                        <span class="detail-val">👥 ${s.players} / ${s.max_players}</span>
                    </div>
                    <div class="detail-item">
                        <span class="detail-label">Огонь по своим</span>
                        <span class="detail-val">${ffText}</span>
                    </div>
                </div>

                <div class="card-footer">
                    <div class="ip-container">
                        <span>🌐 ${fullAddress}</span>
                    </div>
                    <button class="btn-copy" onclick="copyToClipboard('${fullAddress}')">
                        Копировать IP
                    </button>
                </div>
            </div>
        `;
    }).join('');
}

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        showToast(`IP ${text} скопирован!`);
    }).catch(err => {
        console.error('Copy failed:', err);
    });
}

function showToast(msg) {
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
searchInput.addEventListener('input', renderServers);
modeFilter.addEventListener('change', renderServers);
refreshBtn.addEventListener('click', () => {
    loadingEl.classList.remove('hidden');
    fetchServers();
});

// Auto-refresh every 3 seconds
fetchServers();
setInterval(fetchServers, 3000);
