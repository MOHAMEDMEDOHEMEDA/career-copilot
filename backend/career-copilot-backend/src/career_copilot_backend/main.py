from fastapi import FastAPI

app = FastAPI(
    title="Career Copilot API",
    description="AI-powered career assistant",
    version="1.0.0"
)


@app.get("/")
async def root():
    return {"message": "Career Copilot API is running!"}


@app.get("/health")
async def health_check():
    return {"status": "healthy"}