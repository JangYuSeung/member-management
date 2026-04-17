# DB 연결 설정과 세션 관리를 담당하는 모듈
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# 이전 흐름:
# 1. secret.yaml에서 DATABASE_URL 환경변수에 DB 엔드포인트 넣어서 secret 생성
# 2. deployment.yaml에서 env: 설정으로 DATABASE_URL 환경변수를 FastAPI 컨테이너에 주입
# 즉, fastapi deployment 파드가 생성될 때 위 환경변수가 컨테이너에 주입됨

# 결과적으로, 컨테이너 내부의 DATABASE_URL 환경변수에서 DB엔드포인트를 읽어옴
engine = create_engine(os.getenv("DATABASE_URL")) 
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()