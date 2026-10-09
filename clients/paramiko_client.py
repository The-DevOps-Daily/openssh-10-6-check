"""Connect with paramiko, run `true`. Usage: paramiko_client.py <port> <user> <key>"""
import sys

import paramiko

port, user, key = int(sys.argv[1]), sys.argv[2], sys.argv[3]
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())  # throwaway local test server
c.connect("127.0.0.1", port=port, username=user, key_filename=key, look_for_keys=False, allow_agent=False)
_, out, _ = c.exec_command("true")
out.channel.recv_exit_status()
print("kex:", c.get_transport().kex_engine.__class__.__name__)
c.close()
