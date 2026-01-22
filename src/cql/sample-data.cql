-- sample-data.cql
-- A simple script to create a test keyspace, table, and load sample data.
-- You can run this file using cqlsh. For example:
-- cqlsh -u cassandra -p 'YourPassword' -f /path/to/this/file/src/cql/sample-data.cql

-- 1. Create a test keyspace
-- Using SimpleStrategy is fine for single-datacenter test environments.
CREATE KEYSPACE IF NOT EXISTS my_app
  WITH REPLICATION = {
    'class' : 'SimpleStrategy',
    'replication_factor' : 3
  };

-- Use the new keyspace
USE my_app;

-- 2. Create a users table
CREATE TABLE IF NOT EXISTS users (
  user_id UUID,
  first_name TEXT,
  last_name TEXT,
  email TEXT,
  created_at TIMESTAMP,
  PRIMARY KEY (user_id)
);

-- 3. Insert some sample data
-- Note: In cqlsh, the uuid() function generates a new unique identifier.
INSERT INTO users (user_id, first_name, last_name, email, created_at) VALUES (uuid(), 'John', 'Doe', 'john.doe@example.com', toTimestamp(now()));
INSERT INTO users (user_id, first_name, last_name, email, created_at) VALUES (uuid(), 'Jane', 'Smith', 'jane.smith@example.com', toTimestamp(now()));
INSERT INTO users (user_id, first_name, last_name, email, created_at) VALUES (uuid(), 'Peter', 'Jones', 'peter.jones@example.com', toTimestamp(now()));
INSERT INTO users (user_id, first_name, last_name, email, created_at) VALUES (uuid(), 'Alice', 'Williams', 'alice.williams@example.com', toTimestamp(now()));

-- You can verify the data was loaded with:
-- SELECT * FROM my_app.users;