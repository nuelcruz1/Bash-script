from flask import Flask
import os

app = Flask(__name__)

# Define the message and environment details
COMMIT_HASH = os.environ.get('COMMIT_HASH', 'unknown')

@app.route('/')
def home():
    html = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>DevOps Deployment Success</title>
        <style>
            body {{
                font-family: 'Arial', sans-serif;
                background-color: #e6f7ff;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
                text-align: center;
            }}
            .container {{
                background-color: #ffffff;
                padding: 40px;
                border-radius: 12px;
                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
                border-left: 8px solid #007bff;
            }}
            h1 {{
                color: #007bff;
                font-size: 2.5em;
                margin-bottom: 10px;
            }}
            p {{
                color: #555;
                font-size: 1.1em;
                margin-top: 5px;
            }}
            .version {{
                margin-top: 20px;
                padding-top: 15px;
                border-top: 1px dashed #ccc;
                color: #0056b3;
                font-size: 0.9em;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Deployment Successful </h1>
            <p>This Python application is now running inside a Docker container.</p>
            <p>The Nginx Reverse Proxy is successfully forwarding traffic to me.</p>
            <div class="version">
                Application running on internal container port: 80
                <br>
            
            </div>
        </div>
    </body>
    </html>
    """
    return html

if __name__ == '__main__':
    # Running on all interfaces (0.0.0.0) and on the requested port (80)
    app.run(debug=True, host='0.0.0.0', port=80)