# Tribune

### Dependencies

You'll need to install ruby and node first, then run `rake install`. Create a `config.yaml` file from the `config.yaml.example` template. Run `rake db:create` to create the database and tables.

### Starting the server

Start the server with `rake server:run`.

### Running the UI

Run the iOS app with `rake ui:run_ios` and the Android app with `rake ui:run_android`. If you encounter errors, try running `rake ui:doctor`. Note that in the iOS simulator, you can connect to a local server with `http://localhost:1847`, but in the Android simulator, you'll need to use `http://192.168.X.Y:1847` (or whatever your computer's IP is).

### Creating a User

Run `rake user:create` and it will prompt you for a username and password.

### Running the tests

Ensure the test database is created with `rake testdb:create`, then run `rake server:spec`.
