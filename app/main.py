from fastapi import FastAPI

app = FastAPI(title="Signed and Guarded Demo Service")

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Running securely inside signed-and-guarded cluster"}

@app.get("/healthz")
def healthz():
    return {"status": "healthy"}
