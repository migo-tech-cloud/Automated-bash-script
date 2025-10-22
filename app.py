from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "🚀 HNG DevOps Stage 1 — Automated Deployment Successful!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)

