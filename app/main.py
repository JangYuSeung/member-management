# fastapi의 진입점
from fastapi import FastAPI
from database import Base, engine
from routers.members import router

Base.metadata.create_all(bind=engine)

# FastAPI가 자신이 /management 하위에서 동작한다는 걸 인식하는 용도 = root_path 설정
app = FastAPI(root_path="/management") # root_path는 경로 변환에 관여하지 않고, nginx의 proxy_pass 끝 슬래시가 경로 변환을 담당
app.include_router(router)

@app.get("/health")
def health():
    return {"status": "ok"}