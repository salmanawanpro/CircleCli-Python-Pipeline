import os

from flask import Flask, jsonify, request
from sqlalchemy import Column, Integer, String, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/app"
)

engine = create_engine(DATABASE_URL)
Session = sessionmaker(bind=engine)
Base = declarative_base()


class Widget(Base):
    __tablename__ = "widgets"
    id = Column(Integer, primary_key=True)
    name = Column(String(80), nullable=False)


Base.metadata.create_all(engine)

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/widgets", methods=["GET"])
def list_widgets():
    session = Session()
    try:
        widgets = session.query(Widget).all()
        return jsonify([{"id": w.id, "name": w.name} for w in widgets])
    finally:
        session.close()


@app.route("/widgets", methods=["POST"])
def create_widget():
    data = request.get_json(force=True)
    session = Session()
    try:
        widget = Widget(name=data["name"])
        session.add(widget)
        session.commit()
        return jsonify({"id": widget.id, "name": widget.name}), 201
    finally:
        session.close()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
