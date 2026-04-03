- Use `uv` as package manager.
- Keep unit test updated and fast.
- IMPORTANT: When fixing stuff, always run docker compose up to certify no errors on docker startup.
- If a container is slow at starting up, find a way to ship it faster. 
- After containers started, always try and run a test to certify pipelines works fine (in an end-to-end manner live)

