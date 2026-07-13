import os

from flask import Flask, jsonify, request
from sqlalchemy import Column, Integer, String, create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker

Base = declarative_base()
Session = sessionmaker()

_engine = None


class Widget(Base):
    __tablename__ = "widgets"
    id = Column(Integer, primary_key=True)
    name = Column(String(80), nullable=False)


def get_database_url():
    return os.environ.get(
        "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/app"
    )


def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(get_database_url())
        Session.configure(bind=_engine)
    return _engine


def init_db():
    Base.metadata.create_all(get_engine())


def create_app():
    application = Flask(__name__)
    application.config["DB_INITIALIZED"] = False

    @application.before_request
    def ensure_schema():
        # Keep /health independent of the database so liveness checks stay cheap.
        if request.path == "/health":
            return
        if not application.config["DB_INITIALIZED"]:
            init_db()
            application.config["DB_INITIALIZED"] = True

    @application.route("/health")
    def health():
        return jsonify(status="ok")

    @application.route("/ready")
    def ready():
        try:
            with get_engine().connect() as conn:
                conn.execute(text("SELECT 1"))
            return jsonify(status="ready")
        except Exception as exc:  # noqa: BLE001 - surface DB readiness failures
            return jsonify(status="not_ready", error=str(exc)), 503

    @application.route("/widgets", methods=["GET"])
    def list_widgets():
        session = Session()
        try:
            widgets = session.query(Widget).all()
            return jsonify([{"id": w.id, "name": w.name} for w in widgets])
        finally:
            session.close()

    @application.route("/widgets", methods=["POST"])
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

    return application


# Vercel (and gunicorn) look for a module-level Flask instance named `app`.
app = create_app()


if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port)
