# Use the official Python image as the base
FROM python:3.11-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install dependencies
# We install dependencies before copying the rest of the code to leverage Docker's caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Set the environment variable for the application to run in production mode
ENV FLASK_APP=app.py
ENV FLASK_RUN_HOST=0.0.0.0

# Expose the internal container port (Crucial input for your deploy.sh script)
EXPOSE 80

# Command to run the application using the standard Flask development server
# In a true production environment, you would use a dedicated WSGI server like Gunicorn
CMD ["flask", "run", "--port", "80"]