# Tribune

### Dependencies

You'll need to install ruby and node first, then run `rake install`. Create a `config.yaml` file from the `config.yaml.example` template. Run `rake db:create` to create the database and tables.

### Starting the server

Start the server with `rake server:run`.

### Running the UI

Start the UI in development mode with `rake ui:run`. The react native CLI should provide options to launch on iOS/Android/etc.

### Running the tests

Ensure the test database is created with `rake testdb:create`, then run `rake server:spec`.
