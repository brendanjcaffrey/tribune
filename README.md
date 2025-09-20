# Tribune

### Dependencies

You'll need to install ruby and node first, then run `rake install`. Create a `config.yaml` file from the `config.yaml.example` template. Run `rake db:create` to create the database and tables.

### Starting the server

Start the server with `rake server:run`.

### Running the web UI

Start the UI in development mode with `rake web:vite`. The website should be available at `http://localhost:1848`.

### Accessing the web UI remotely

If you want to test on a tablet for example, you need to put a proxy like nginx in front of the vite server that handles TLS termination for you. `navigator.storage` is only available in secure contexts (`http://localhost` and `https://`), which the web app depends on. An example nginx config for development on macOS with tailscale is in this repository at `nginx-development.conf.example`. Make sure to uncomment the `allowedHosts: true` line in `web/vite.config.ts` as well.

To remotely debug an Android tablet, first enable Developer Mode and then USB Debugging in Android settings. Then enable USB Debugging in the Android Firefox settings. Finally, connect the device and go to `about:debugging` in macOS Firefox and connect to the device.

### Creating a User

Run `rake user:create` and it will prompt you for a username and password.

### Running the tests

Ensure the test database is created with `rake testdb:create`, then run `rake server:spec`. The web tests can be run with `rake web:vitest`.
