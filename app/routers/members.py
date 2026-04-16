from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
import hashlib
from database import get_db
from models import Member
from schemas import MemberCreate, MemberUpdate, PasswordChange, MemberResponse

router = APIRouter(prefix="/members", tags=["members"], redirect_slashes=False)

def hash_pw(pw: str):
    return hashlib.sha256(pw.encode()).hexdigest()

@router.post("/", response_model=MemberResponse)
def create_member(data: MemberCreate, db: Session = Depends(get_db)):
    if db.query(Member).filter((Member.username == data.username) | (Member.email == data.email)).first():
        raise HTTPException(400, "이미 존재하는 아이디 또는 이메일")
    member = Member(**data.dict(exclude={"password"}), password=hash_pw(data.password))
    db.add(member); db.commit(); db.refresh(member)
    return member

@router.get("/", response_model=List[MemberResponse])
def list_members(db: Session = Depends(get_db)):
    return db.query(Member).all()

@router.get("/{id}", response_model=MemberResponse)
def get_member(id: int, db: Session = Depends(get_db)):
    m = db.query(Member).filter(Member.id == id).first()
    if not m: raise HTTPException(404, "회원 없음")
    return m

@router.put("/{id}", response_model=MemberResponse)
def update_member(id: int, data: MemberUpdate, db: Session = Depends(get_db)):
    m = db.query(Member).filter(Member.id == id).first()
    if not m: raise HTTPException(404, "회원 없음")
    for k, v in data.dict(exclude_none=True).items():
        setattr(m, k, v)
    db.commit(); db.refresh(m)
    return m

@router.put("/{id}/password")
def change_password(id: int, data: PasswordChange, db: Session = Depends(get_db)):
    m = db.query(Member).filter(Member.id == id).first()
    if not m: raise HTTPException(404, "회원 없음")
    if m.password != hash_pw(data.current_password):
        raise HTTPException(400, "현재 비밀번호 불일치")
    m.password = hash_pw(data.new_password)
    db.commit()
    return {"message": "비밀번호 변경 완료"}

@router.delete("/{id}")
def delete_member(id: int, db: Session = Depends(get_db)):
    m = db.query(Member).filter(Member.id == id).first()
    if not m: raise HTTPException(404, "회원 없음")
    db.delete(m); db.commit()
    return {"message": "탈퇴 완료"}