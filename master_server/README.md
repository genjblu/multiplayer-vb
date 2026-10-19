# Master Server & Live Tracker (Веб-сервер мониторинга)

Бэкенд мастер-сервера и веб-сайт мониторинга активных серверов для вашего мультиплеерного шутера Godot 4.

## Возможности
- 🌐 **Веб-дашборд**: список серверов в реальном времени, количество игроков, карта, режим, статус (В игре / В лобби), кнопка копирования IP в один клик.
- 📡 **REST API для игры**:
  - `GET /api/servers` — получение списка всех активных комнат.
  - `POST /api/servers/register` — регистрация нового сервера (хоста). Автоматически определяет внешний публичный IP.
  - `POST /api/servers/heartbeat` — отправка пульса каждые 5-10 секунд с актуальным числом игроков.
  - `POST /api/servers/unregister` — удаление сервера при закрытии.
  - `GET /api/stats` — статистика (всего серверов, всего игроков онлайн).
- 🧹 **Автоочистка**: «упавшие» или закрытые сервера автоматически удаляются из списка через 20 секунд отсутствия сигнала.

---

## 1. Запуск локально (для тестов)
```bash
cd master_server
npm install
node server.js
```
Сайт откроется по адресу: `http://localhost:3000`

---

## 2. Бесплатный деплой в интернет за 2 минуты (0 рублей)

### Вариант А: Render.com (Бесплатно навсегда)
1. Загрузите ваш репозиторий на **GitHub**.
2. Зарегистрируйтесь на [Render.com](https://render.com) (через GitHub).
3. Нажмите **New +** -> **Web Service**.
4. Выберите ваш репозиторий.
5. Настройки:
   - **Root Directory**: `master_server`
   - **Build Command**: `npm install`
   - **Start Command**: `node server.js`
   - **Instance Type**: `Free`
6. Нажмите **Create Web Service**. Через 1 минуту у вас будет рабочий HTTPS-сайт: `https://my-game-servers.onrender.com`.

### Вариант Б: На собственном VPS (Oracle Always Free или любой Linux)
```bash
cd master_server
npm install
# Запуск в фоновом режиме через pm2 или systemd:
sudo npm install -g pm2
pm2 start server.js --name "master-server"
pm2 startup
pm2 save
```
