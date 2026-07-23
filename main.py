from langchain_core.messages import AIMessage
from uuid import uuid4
import os

from graph.builder import fluxo_agentes
from config.docker import garantir_banco
from tools.postgres.connection import get_conn
from tools.postgres.context import session_context
from tools.postgres.helpers import resolve_stock_id
import tools.mongo.chats.core as chats
import tools.mongo.users.core as perfis
from tools.mongo.chats.schemas import Mensagem, Role

from ui.terminal import (
    exibir_titulo,
    exibir_usuario,
    exibir_assistente,
    console,
)


# --------------------- FIX WARNING ---------------------
import logging
import warnings

warnings.filterwarnings("ignore", message="Deserializing unregistered type")
logging.getLogger("langgraph").setLevel(logging.ERROR)
# --------------------- FIX WARNING ---------------------


# Usuário fixo para rodar a demo localmente sem tela de login. `users.id` é
# INTEGER PRIMARY KEY sem SERIAL no schema (data/sql/schema.sql), por isso
# criamos o registro (e o grupo/estoque associados) na primeira execução.
DEMO_USER_ID = 1


def _garantir_usuario_demo(user_id: int = DEMO_USER_ID) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM users WHERE id = %s;", (user_id,))
            if cur.fetchone():
                return

            cur.execute(
                """
                INSERT INTO users (id, name, account_type, email, hash_password)
                VALUES (%s, %s, 'Pessoal', %s, %s);
                """,
                (user_id, "Usuário Demo", "demo@frigus.local", "demo-hash"),
            )
            cur.execute("INSERT INTO groups (id, name) VALUES (%s, %s) ON CONFLICT (id) DO NOTHING;", (user_id, "Minha Casa"))
            cur.execute("INSERT INTO stocks (id, group_id) VALUES (%s, %s) ON CONFLICT (id) DO NOTHING;", (user_id, user_id))
            cur.execute(
                "INSERT INTO user_groups (id, user_id, group_id) VALUES (%s, %s, %s) ON CONFLICT (user_id, group_id) DO NOTHING;",
                (user_id, user_id, user_id),
            )
            conn.commit()


def montar_mensagem_humana(conteudo: str) -> Mensagem:
    return Mensagem(
        role=Role.HUMAN,
        content=conteudo
    )


def salvar_mensagens(user_id: int, session_id: str, mensagens: list[Mensagem]) -> None:
    if not chats.buscar(session_id):
        chats.criar(user_id, session_id, mensagens)
    else:
        chats.atualizar_mensagens(session_id, mensagens)


def _extrair_resposta(estado_final: dict) -> str | None:
    for msg in estado_final["messages"][::-1]:
        if isinstance(msg, AIMessage):
            return msg.content
    return None


def executar_fluxo_frigus(
    pergunta_usuario: str,
    session_id: str,
    user_id: int,
    stock_id: int | None,
) -> str:

    nova_msg = montar_mensagem_humana(pergunta_usuario)
    perfil = perfis.buscar_perfil(user_id)

    estado_inicial = {
        "messages":         [nova_msg.para_langchain()],
        "agentes_chamados": [],
        "perfil_usuario":   perfil,
        "stock_id":         stock_id,
        "tentativas_juiz":  0,
    }

    # stock_id/user_id ficam disponíveis via contextvars para as tools de
    # Postgres (tools/postgres/context.py) durante toda a invocação do grafo.
    with session_context(user_id=user_id, stock_id=stock_id):
        estado_final = fluxo_agentes.invoke(
            estado_inicial,
            config={"configurable": {"thread_id": session_id}},
        )

    resposta = _extrair_resposta(estado_final)

    if not resposta:
        return "Sem resposta."

    novas = [nova_msg, Mensagem(role=Role.AI, content=resposta)]
    salvar_mensagens(user_id, session_id, novas)

    return resposta


def main() -> None:
    os.system("cls")

    garantir_banco()
    _garantir_usuario_demo()
    exibir_titulo()

    user_id = DEMO_USER_ID
    session_id = str(uuid4())

    perfis.garantir_perfil(user_id)

    with get_conn() as conn:
        with conn.cursor() as cur:
            stock_id = resolve_stock_id(cur, user_id)

    while True:
        try:
            user_input = console.input("[bold green]>[/bold green] ").strip()

            if user_input == "/exit":
                chats.encerrar_sessao(session_id, user_id)
                console.print("\n[dim]Encerrando...[/dim]")
                break

            if not user_input:
                continue

            exibir_usuario(user_input)
            resposta = executar_fluxo_frigus(user_input, session_id=session_id, user_id=user_id, stock_id=stock_id)
            exibir_assistente(resposta)

        except KeyboardInterrupt:
            chats.encerrar_sessao(session_id, user_id)
            console.print("\n[dim]Encerrando...[/dim]")
            break
        except Exception as e:
            console.print(f"[bold red]Erro:[/bold red] {e}")


if __name__ == "__main__":
    main()
