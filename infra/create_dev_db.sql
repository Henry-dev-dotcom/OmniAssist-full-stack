-- Local development only: the omni/omni user from infra/env/.env.example.
-- Run as a PostgreSQL superuser, e.g. psql -U postgres -f infra/create_dev_db.sql
-- CREATEDB lets the integration tests make and drop throwaway databases.
CREATE ROLE omni LOGIN CREATEDB PASSWORD 'omni';
CREATE DATABASE omniassist OWNER omni;
