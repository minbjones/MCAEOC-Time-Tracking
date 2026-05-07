import json
from math import sqrt

import cv2
import numpy as np
from deepface import DeepFace

from config import settings


class OpenSourceFaceService:
    def __init__(self):
        self.model_name = settings.face_model_name
        self.detector_backend = settings.face_detector_backend
        self.align = settings.face_align
        self.enforce_detection = settings.face_enforce_detection
        self.expand_percentage = settings.face_expand_percentage
        self.max_image_size = settings.face_max_image_size

    def is_configured(self) -> bool:
        return True

    def _normalization(self) -> str:
        if self.model_name.lower() == "arcface":
            return "ArcFace"
        if self.model_name.lower() == "facenet":
            return "Facenet"
        if self.model_name.lower() == "facenet512":
            return "Facenet2018"
        return "base"

    def _resize_if_needed(self, image):
        height, width = image.shape[:2]
        longest_side = max(height, width)
        if longest_side <= self.max_image_size:
            return image

        scale = self.max_image_size / float(longest_side)
        resized_width = max(1, int(width * scale))
        resized_height = max(1, int(height * scale))
        return cv2.resize(image, (resized_width, resized_height), interpolation=cv2.INTER_AREA)

    def represent(self, image_bytes: bytes) -> list[float]:
        np_buffer = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(np_buffer, cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("Could not read face image.")
        image = self._resize_if_needed(image)

        try:
            result = DeepFace.represent(
                img_path=image,
                model_name=self.model_name,
                detector_backend=self.detector_backend,
                enforce_detection=self.enforce_detection,
                align=self.align,
                expand_percentage=self.expand_percentage,
                normalization=self._normalization(),
            )
        except Exception as exc:
            raise ValueError(str(exc)) from exc

        if not result:
            raise ValueError("No face embedding could be created from that image.")
        if isinstance(result, list):
            embedding = result[0]["embedding"]
        else:
            embedding = result["embedding"]
        return [float(value) for value in embedding]

    @staticmethod
    def embedding_to_json(embedding: list[float]) -> str:
        return json.dumps(embedding)

    @staticmethod
    def embedding_from_json(embedding_json: str) -> list[float]:
        return [float(value) for value in json.loads(embedding_json)]

    @staticmethod
    def cosine_distance(embedding_a: list[float], embedding_b: list[float]) -> float:
        dot = sum(a * b for a, b in zip(embedding_a, embedding_b))
        norm_a = sqrt(sum(a * a for a in embedding_a))
        norm_b = sqrt(sum(b * b for b in embedding_b))
        if norm_a == 0 or norm_b == 0:
            return 1.0
        similarity = dot / (norm_a * norm_b)
        return 1.0 - similarity

    def compare(self, probe_embedding: list[float], stored_embedding: list[float]) -> tuple[bool, float, float]:
        distance = self.cosine_distance(probe_embedding, stored_embedding)
        confidence = max(0.0, min(1.0, 1.0 - distance))
        matched = distance <= settings.face_distance_threshold
        return matched, confidence, distance
