# Tribune

### Dependencies

You'll need to install ruby and node first, then run `rake install`. Create a `config.yaml` file from the `config.yaml.example` template. Run `rake db:create` to create the database and tables.

Note that the server needs node at runtime, not just to build: article extraction runs [@mozilla/readability](https://github.com/mozilla/readability) in a subprocess. `rake install` installs it into `server/extract/`.

### Starting the server

Start the server with `rake server:run`.

### Running background jobs

Epub extraction jobs run via [que](https://github.com/que-rb/que), which stores its queue in Postgres. Start a worker with `rake que:work` (set `QUE_WORKER_COUNT` to change the pool size, default 6). **Nothing pushed to `POST /newsletters/raw` turns into an epub until a worker is running.**

A job that fails is retried three times and then left alone; the newsletter keeps its url as a title and has no epub to download. Look in the worker's output for what went wrong, or at `last_error_message` in the `que_jobs` table.

Que and que-scheduler keep their own tables out of `schema.sql` and manage them with their own migrations. `rake db:create` and `rake db:init` apply them; `rake db:que_migrate` (and `rake testdb:que_migrate`) apply them on their own, which is what you want after upgrading either gem.

Recurring jobs are scheduled by [que-scheduler](https://github.com/hlascelles/que-scheduler), which is a que job itself: it wakes up, enqueues whatever is due and re-enqueues itself, so it needs no process of its own. The schedule is `server/que_schedule.yml`, in crontab syntax and in UTC. Nothing recurring runs until a worker is running either.

### Site configs

`ftr_site_config_dir` in the config should point to a clone of [ftr-site-config](https://github.com/fivefilters/ftr-site-config). In that repo, there's one `<host>.txt` per site saying, where that site keeps its article and what to throw away, which beats readability inferring it from text density. If you set the key to a blank string, the server will only use readability.

A que worker runs `git pull` in that clone once a day, so it doesn't go stale. If `ftr_site_config_dir` is blank or missing, the job says so and does nothing.

### Running the production server

Put nginx in front of the web server using `tribune.conf.example` as a guide. Run `rake web:build` to build the static files for the web app, which are also served through nginx. Set `server_accel` to `true` in `config.yaml` if you do this to speed up delivery of the epub & source files.

`tribune.conf.example` contains a plain http listener for a jailbroken Kindle running the Tailscale KOReader plugin in network mode. Point the plugin at this port and set the web proxy to `http://localhost:1056`.

### Running the development web UI

Start the UI in development mode with `rake web:vite`. The website should be available at `http://localhost:1848`.

### Accessing the development web UI remotely

If you want to reach a dev server on a tablet for example, you need to put a proxy like nginx in front of the vite server that handles TLS termination for you. `navigator.storage` is only available in secure contexts (`http://localhost` and `https://`), which the web app depends on. `tribune-dev.conf.example` is an example for macOS with tailscale, terminating TLS in front of the vite server. Make sure to uncomment the `allowedHosts: true` line in `web/vite.config.ts` as well.

To remotely debug an Android tablet, first enable Developer Mode and then USB Debugging in Android settings. Then enable USB Debugging in the Android Firefox settings. Finally, connect the device and go to `about:debugging` in macOS Firefox and connect to the device.

If you're trying to advance to the next page in an ebook and the browser is closing/going to the previous page, this is an Android thing. In Settings, search for "System navigation", go to "Gesture navigation" settings and disable "Back Sensitivity/Left edge".

### Running the iOS UI

First, copy `ios/Tribune/Config.xcconfig.example` to `ios/Tribune/Config.xcconfig` and update it to point at your api server. Then open the app in Xcode and run.

### Running the KOReader plugin

The plugin is `koreader/tribune.koplugin`. KOReader loads plugins from the `plugins` directory in its data directory, so installing it means putting that directory there and restarting KOReader:

- macOS release build (`KOReader.app`): `~/Library/Application Support/koreader/plugins/`
- Kindle: `/mnt/us/koreader/plugins/`
- Android: `koreader/plugins/` in the app's storage directory

On macOS, `rake koreader:install` symlinks the plugin into `~/Library/Application Support/koreader/plugins/`. `COPY=1 rake koreader:install` installs a real copy instead of a symlink. Set `KO_HOME` to override the data directory. Run `rake koreader:run` to launch the macOS app with verbose logs printed in the terminal. Enable verbose logs by clicking the top of the screen, hitting the menu icon on the right, Help > Report a Bug > Enable verbose logging.

The plugin's entry is in the file browser's menu under `Tools`. Set the server address first, then sign in with the same username and password as the web app. The token is kept in `settings/tribune.lua` in KOReader's data directory and survives a restart; signing out discards it.

The two devices reach the server differently. An Android tablet can run a full Tailscale tunnel and use the https address (`https://<host>.ts.net:1847`). The Kindle may run Tailscale in userspace networking mode and need to use plain http, with KOReader's `Network → HTTP proxy` set to `http://localhost:1056`.

### Creating a User

Run `rake user:create` and it will prompt you for a username and password.

### Running the tests

Ensure the test database is created with `rake testdb:create`, then run `rake server:spec`. The web tests can be run with `rake web:vitest`.
