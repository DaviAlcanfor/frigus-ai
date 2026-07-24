-- =========================================================
-- Script de criação de schema (DDL) - 20 tabelas + 9 enums
-- Tudo em snake_case, FKs inline, ordem topológica
-- =========================================================

BEGIN;

-- =========================================================
-- RESET DE SCHEMA (roda toda vez que quiser recriar do zero)
-- Isolado num schema próprio, não encosta no "public"
-- =========================================================

DROP SCHEMA IF EXISTS dataload CASCADE;
CREATE SCHEMA dataload;
SET search_path TO dataload;

-- ---- 00_enums.sql ----
CREATE TYPE account_type_enum AS ENUM ('Pessoal', 'Empresarial', 'Convidado');
CREATE TYPE category_enum AS ENUM ('Fruta', 'Verdura', 'Laticínio', 'Carne', 'Grão', 'Bebida', 'Limpeza', 'Higiene Pessoal');
CREATE TYPE storage_place_enum AS ENUM ('Geladeira', 'Freezer', 'Despensa', 'Armário', 'Prateleira');
CREATE TYPE product_status_enum AS ENUM ('Fresco', 'Próximo do vencimento', 'Vencido');
CREATE TYPE list_status_enum AS ENUM ('Aberta', 'Concluída', 'Cancelada');
CREATE TYPE product_list_status_enum AS ENUM ('Pendente', 'Comprado', 'Removido');
CREATE TYPE movement_type_enum AS ENUM ('Entrada', 'Saída', 'Ajuste');
CREATE TYPE conversation_type_enum AS ENUM ('Privada', 'Grupo');
CREATE TYPE message_type_enum AS ENUM ('Texto', 'Imagem', 'Sistema');

-- ---- 01_groups.sql ----
CREATE TABLE groups (
    id              INTEGER PRIMARY KEY,
    name            VARCHAR NOT NULL,
    banner_picture  TEXT
);

-- ---- 02_recipes.sql ----
CREATE TABLE recipes (
    id              INTEGER PRIMARY KEY,
    name            VARCHAR NOT NULL,
    description     TEXT,
    instructions    TEXT,
    domestic_only   BOOLEAN NOT NULL DEFAULT TRUE,
    active          BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---- 03_users.sql ----
CREATE TABLE users (
    id              INTEGER PRIMARY KEY,
    name            VARCHAR NOT NULL,
    birth_date      DATE,
    account_type    account_type_enum NOT NULL,
    email           VARCHAR NOT NULL,
    hash_password   VARCHAR NOT NULL,
    CONSTRAINT uq_users_email UNIQUE (email)
);

-- ---- 04_stocks.sql ----
CREATE TABLE stocks (
    id       INTEGER PRIMARY KEY,
    group_id INTEGER NOT NULL,
    CONSTRAINT fk_stocks_group_id_groups
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
);

-- ---- 05_products.sql ----
CREATE TABLE products (
    id             INTEGER PRIMARY KEY,
    name           VARCHAR NOT NULL,
    category       category_enum NOT NULL,
    storage_place  storage_place_enum NOT NULL,
    unit_price     DECIMAL NOT NULL
);

-- ---- 06_accounts.sql ----
CREATE TABLE accounts (
    id            INTEGER PRIMARY KEY,
    account_type  account_type_enum NOT NULL,
    user_id       INTEGER NOT NULL,
    name          VARCHAR NOT NULL,
    CONSTRAINT fk_accounts_user_id_users
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ---- 07_user_groups.sql ----
CREATE TABLE user_groups (
    id       INTEGER PRIMARY KEY,
    user_id  INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    CONSTRAINT uq_user_groups_user_group UNIQUE (user_id, group_id),
    CONSTRAINT fk_user_groups_user_id_users
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_groups_group_id_groups
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
);

-- ---- 08_stock_products.sql ----
CREATE TABLE stock_products (
    id                  INTEGER PRIMARY KEY,
    product_id          INTEGER NOT NULL,
    stock_id            INTEGER NOT NULL,
    quantity            INTEGER NOT NULL,
    minimal_quantity    INTEGER,
    expire_date         DATE NOT NULL,
    product_status      product_status_enum,
    category            category_enum NOT NULL,
    CONSTRAINT uq_stock_products_product_stock_expire UNIQUE (product_id, stock_id, expire_date),
    CONSTRAINT fk_stock_products_product_id_products
        FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_stock_products_stock_id_stocks
        FOREIGN KEY (stock_id) REFERENCES stocks (id) ON DELETE CASCADE
);

-- ---- 09_recipe_ingredients.sql ----
CREATE TABLE recipe_ingredients (
    id          INTEGER PRIMARY KEY,
    recipe_id   INTEGER NOT NULL,
    product_id  INTEGER NOT NULL,
    quantity    DECIMAL,
    unit        VARCHAR,
    required    BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_recipe_ingredients_recipe_product UNIQUE (recipe_id, product_id),
    CONSTRAINT fk_recipe_ingredients_recipe_id_recipes
        FOREIGN KEY (recipe_id) REFERENCES recipes (id) ON DELETE CASCADE,
    CONSTRAINT fk_recipe_ingredients_product_id_products
        FOREIGN KEY (product_id) REFERENCES products (id)
);

-- ---- 10_recipe_suggestions.sql ----
CREATE TABLE recipe_suggestions (
    id                    INTEGER PRIMARY KEY,
    recipe_id             INTEGER NOT NULL,
    stock_id              INTEGER NOT NULL,
    matched_ingredients   INTEGER NOT NULL DEFAULT 0,
    missing_ingredients   INTEGER NOT NULL DEFAULT 0,
    nearest_expire_date   DATE,
    score                 DECIMAL,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_recipe_suggestions_recipe_id_recipes
        FOREIGN KEY (recipe_id) REFERENCES recipes (id) ON DELETE CASCADE,
    CONSTRAINT fk_recipe_suggestions_stock_id_stocks
        FOREIGN KEY (stock_id) REFERENCES stocks (id) ON DELETE CASCADE
);

-- ---- 11_shopping_lists.sql ----
CREATE TABLE shopping_lists (
    id        INTEGER PRIMARY KEY,
    date      DATE NOT NULL DEFAULT CURRENT_DATE,
    stock_id  INTEGER NOT NULL,
    status    list_status_enum NOT NULL,
    CONSTRAINT fk_shopping_lists_stock_id_stocks
        FOREIGN KEY (stock_id) REFERENCES stocks (id) ON DELETE CASCADE
);

-- ---- 12_conversations.sql ----
CREATE TABLE conversations (
    id                  SERIAL PRIMARY KEY,
    conversation_type   conversation_type_enum NOT NULL,
    group_id            INTEGER,
    name                VARCHAR,
    pair_key            VARCHAR,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_pair UNIQUE (pair_key),
    CONSTRAINT fk_conversations_group_id_groups
        FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE SET NULL
);

-- ---- 13_discard.sql ----
CREATE TABLE discard (
    id                INTEGER PRIMARY KEY,
    stock_product_id  INTEGER NOT NULL,
    reason            TEXT,
    date              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_discard_stock_product_id_stock_products
        FOREIGN KEY (stock_product_id) REFERENCES stock_products (id) ON DELETE CASCADE
);

-- ---- 14_shopping_list_products.sql ----
CREATE TABLE shopping_list_products (
    id          INTEGER PRIMARY KEY,
    list_id     INTEGER NOT NULL,
    product_id  INTEGER NOT NULL,
    status      product_list_status_enum,
    quantity    INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT uq_shopping_list_products_list_product UNIQUE (list_id, product_id),
    CONSTRAINT fk_shopping_list_products_list_id_shopping_lists
        FOREIGN KEY (list_id) REFERENCES shopping_lists (id) ON DELETE CASCADE,
    CONSTRAINT fk_shopping_list_products_product_id_products
        FOREIGN KEY (product_id) REFERENCES products (id)
);

-- ---- 15_stock_movements.sql ----
CREATE TABLE stock_movements (
    id                SERIAL PRIMARY KEY,
    stock_product_id  INTEGER NOT NULL,
    user_id           INTEGER NOT NULL,
    movement_type     movement_type_enum NOT NULL,
    quantity          INTEGER NOT NULL,
    date              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_stock_movements_stock_product_id_stock_products
        FOREIGN KEY (stock_product_id) REFERENCES stock_products (id) ON DELETE CASCADE,
    CONSTRAINT fk_stock_movements_user_id_users
        FOREIGN KEY (user_id) REFERENCES users (id)
);

-- ---- 16_conversation_participants.sql ----
CREATE TABLE conversation_participants (
    conversation_id  INTEGER NOT NULL,
    user_id          INTEGER NOT NULL,
    joined_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at          TIMESTAMP,
    PRIMARY KEY (conversation_id, user_id),
    CONSTRAINT fk_conversation_participants_conversation_id_conversations
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_participants_user_id_users
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ---- 17_messages.sql ----
CREATE TABLE messages (
    id                                  SERIAL PRIMARY KEY,
    conversation_id                     INTEGER NOT NULL,
    sender_id                           INTEGER NOT NULL,
    message_type                        message_type_enum NOT NULL,
    content                             TEXT,
    related_shopping_list_product_id    INTEGER,
    created_at                          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_messages_id_conversation UNIQUE (id, conversation_id),
    CONSTRAINT fk_messages_conversation_id_conversations
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender_id_users
        FOREIGN KEY (sender_id) REFERENCES users (id),
    CONSTRAINT fk_messages_related_shopping_list_product_id_slp
        FOREIGN KEY (related_shopping_list_product_id) REFERENCES shopping_list_products (id) ON DELETE SET NULL,
    -- FK composta: o par (conversation_id, sender_id) precisa existir em conversation_participants
    CONSTRAINT fk_messages_conversation_id_participants
        FOREIGN KEY (conversation_id, sender_id) REFERENCES conversation_participants (conversation_id, user_id)
);

-- ---- 18_message_attachments.sql ----
CREATE TABLE message_attachments (
    id          INTEGER PRIMARY KEY,
    message_id  INTEGER NOT NULL,
    file_url    TEXT NOT NULL,
    file_name   VARCHAR,
    mime_type   VARCHAR NOT NULL,
    file_size   INTEGER,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_message_attachments_message_id_messages
        FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
);

-- ---- 19_message_reads.sql ----
CREATE TABLE message_reads (
    message_id       INTEGER NOT NULL,
    conversation_id  INTEGER NOT NULL,
    user_id          INTEGER NOT NULL,
    read_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    -- FK composta: precisa da UNIQUE (id, conversation_id) que messages já declarou
    CONSTRAINT fk_message_reads_message_id_messages
        FOREIGN KEY (message_id, conversation_id) REFERENCES messages (id, conversation_id) ON DELETE CASCADE,
    -- FK composta: precisa da PK (conversation_id, user_id) que conversation_participants já declarou
    CONSTRAINT fk_message_reads_conversation_id_participants
        FOREIGN KEY (conversation_id, user_id) REFERENCES conversation_participants (conversation_id, user_id) ON DELETE CASCADE
);

-- ---- 20_requests.sql ----
CREATE TABLE requests (
    id               INTEGER PRIMARY KEY,
    user_id          INTEGER NOT NULL,
    product_id       INTEGER NOT NULL,
    stock_id         INTEGER NOT NULL,
    quantity         INTEGER NOT NULL,
    description      TEXT,
    picture          TEXT,
    date             DATE NOT NULL DEFAULT CURRENT_DATE,
    conversation_id  INTEGER,
    message_id       INTEGER,
    CONSTRAINT fk_requests_user_id_users
        FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT fk_requests_product_id_products
        FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_requests_stock_id_stocks
        FOREIGN KEY (stock_id) REFERENCES stocks (id) ON DELETE CASCADE,
    CONSTRAINT fk_requests_conversation_id_conversations
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE SET NULL,
    CONSTRAINT fk_requests_message_id_messages
        FOREIGN KEY (message_id, conversation_id) REFERENCES messages (id, conversation_id) ON DELETE SET NULL
);

-- ---- 21_indexes.sql ----
CREATE INDEX idx_users_email                    ON users (email);
CREATE INDEX idx_accounts_user                  ON accounts (user_id);
CREATE INDEX idx_user_groups_user               ON user_groups (user_id);
CREATE INDEX idx_user_groups_group              ON user_groups (group_id);
CREATE INDEX idx_stocks_group                   ON stocks (group_id);
CREATE INDEX idx_products_category              ON products (category);
CREATE INDEX idx_products_storage_place         ON products (storage_place);
CREATE INDEX idx_stock_products_product         ON stock_products (product_id);
CREATE INDEX idx_stock_products_stock           ON stock_products (stock_id);
CREATE INDEX idx_stock_products_expire_date     ON stock_products (expire_date);
CREATE INDEX idx_stock_products_status          ON stock_products (product_status);
CREATE INDEX idx_recipe_ingredients_recipe      ON recipe_ingredients (recipe_id);
CREATE INDEX idx_recipe_ingredients_product     ON recipe_ingredients (product_id);
CREATE INDEX idx_recipe_suggestions_recipe      ON recipe_suggestions (recipe_id);
CREATE INDEX idx_recipe_suggestions_stock       ON recipe_suggestions (stock_id);
CREATE INDEX idx_recipe_suggestions_expire_date ON recipe_suggestions (nearest_expire_date);
CREATE INDEX idx_shopping_lists_stock           ON shopping_lists (stock_id);
CREATE INDEX idx_shopping_list_products_list    ON shopping_list_products (list_id);
CREATE INDEX idx_shopping_list_products_product ON shopping_list_products (product_id);
CREATE INDEX idx_stock_movements_stock_product  ON stock_movements (stock_product_id);
CREATE INDEX idx_stock_movements_user           ON stock_movements (user_id);
CREATE INDEX idx_stock_movements_date           ON stock_movements (date);
CREATE INDEX idx_conversations_group            ON conversations (group_id);
CREATE INDEX idx_conversation_participants_user ON conversation_participants (user_id);
CREATE INDEX idx_messages_conversation_created  ON messages (conversation_id, created_at);
CREATE INDEX idx_messages_sender                ON messages (sender_id);
CREATE INDEX idx_message_attachments_message    ON message_attachments (message_id);
CREATE INDEX idx_message_reads_user             ON message_reads (user_id);
CREATE INDEX idx_requests_user                  ON requests (user_id);
CREATE INDEX idx_requests_product               ON requests (product_id);
CREATE INDEX idx_requests_stock                 ON requests (stock_id);
CREATE INDEX idx_requests_conversation          ON requests (conversation_id);

COMMIT;
