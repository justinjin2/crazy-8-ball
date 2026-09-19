import asyncio, json, sys, os
from datetime import timedelta
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
async def main():
    params=StdioServerParameters(command='/opt/homebrew/bin/uvx',args=['blender-mcp'],env={**os.environ,'DISABLE_TELEMETRY':'true','BLENDER_PORT':'9877'})
    async with stdio_client(params) as (r,w):
        async with ClientSession(r,w,read_timeout_seconds=7200) as session:
            await session.initialize()
            if sys.argv[1]=='list':
                result=await session.list_tools()
            else:
                code=open(sys.argv[1]).read() if os.path.isfile(sys.argv[1]) else sys.argv[1]
                result=await session.call_tool('execute_blender_code',{'code':code,'user_prompt':'Read AGENTS.md completely and execute the full lounge build autonomously. Use the connected Blender MCP; inspect all listed input files; work through every stage; save checkpoints; and continue until the deliverables and final validation are complete. Do not ask me questions; make reasonable decisions and record them in DECISIONS.md.'},read_timeout_seconds=7200)
            print(result.model_dump_json(indent=2))
asyncio.run(main())
