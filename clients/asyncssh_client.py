"""Connect with asyncssh, run `true`. Usage: asyncssh_client.py <port> <user> <key>"""
import asyncio
import sys

import asyncssh


async def main() -> None:
    port, user, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    async with asyncssh.connect("127.0.0.1", port, username=user, client_keys=[key],
                                known_hosts=None) as conn:  # throwaway local test server
        await conn.run("true", check=True)
        print("kex:", conn.get_extra_info("kex_algorithm") if hasattr(conn, "get_extra_info") else "?")


asyncio.run(main())
