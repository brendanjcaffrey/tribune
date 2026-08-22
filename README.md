# Tribune

### Dependencies

You'll need to install ruby and node first, then run `rake install`. Create a `config.yaml` file from the `config.yaml.example` template. Run `rake db:create` to create the database and tables.

Note that the server needs node at runtime, not just to build: article extraction runs [@mozilla/readability](https://github.com/mozilla/readability) in a subprocess. `rake install` installs it into `server/extract/`.

### Starting the server

Start the server with `rake server:run`.

### Running background jobs

Epub extraction jobs run via [que](https://github.com/que-rb/que), which stores its queue in Postgres. Start a worker with `rake que:work` (set `QUE_WORKER_COUNT` to change the pool size, default 6). **Nothing pushed to `POST /newsletters/raw` turns into an epub until a worker is running.**

A job that fails is retried three times and then left alone; the newsletter keeps its url as a title and has no epub to download. Look in the worker's output for what went wrong, or at `last_error_message` in the `que_jobs` table.

Que keeps its own tables out of `schema.sql` and manages them with its own migrations. `rake db:create` and `rake db:init` apply them; `rake db:que_migrate` (and `rake testdb:que_migrate`) apply them on their own, which is what you want after upgrading the gem.

### Site configs

`ftr_site_config_dir` in the config should point to a clone of [ftr-site-config](https://github.com/fivefilters/ftr-site-config). In that repo, there's one `<host>.txt` per site saying, where that site keeps its article and what to throw away, which beats readability inferring it from text density. If you set the key to a blank string, the server will only use readability.

### Running the web UI

Start the UI in development mode with `rake web:vite`. The website should be available at `http://localhost:1848`.

### Accessing the web UI remotely

If you want to test on a tablet for example, you need to put a proxy like nginx in front of the vite server that handles TLS termination for you. `navigator.storage` is only available in secure contexts (`http://localhost` and `https://`), which the web app depends on. An example nginx config for development on macOS with tailscale is in this repository at `tribune-dev.conf.example`. Make sure to uncomment the `allowedHosts: true` line in `web/vite.config.ts` as well.

To remotely debug an Android tablet, first enable Developer Mode and then USB Debugging in Android settings. Then enable USB Debugging in the Android Firefox settings. Finally, connect the device and go to `about:debugging` in macOS Firefox and connect to the device.

If you're trying to advance to the next page in an ebook and the browser is closing/going to the previous page, this is an Android thing. In Settings, search for "System navigation", go to "Gesture navigation" settings and disable "Back Sensitivity/Left edge".

### Running the iOS UI

First, copy `ios/Tribune/Config.xcconfig.example` to `ios/Tribune/Config.xcconfig` and update it to point at your api server. Then open the app in Xcode and run.

### Creating a User

Run `rake user:create` and it will prompt you for a username and password.

### Running the tests

Ensure the test database is created with `rake testdb:create`, then run `rake server:spec`. The web tests can be run with `rake web:vitest`.
