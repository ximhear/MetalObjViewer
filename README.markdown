#  목적

obj 파일을 읽어서 Metal로 렌더링하는 앱이다.

obj 파일의 다음 정보들을 이용한다.

v (Vertex): 64개 꼭짓점 좌표 (x, y, z)
vn (Vertex Normal): Normal 벡터 정보
vt (Vertex Texture): UV 텍스처 좌표
f (Face): 34개 면 정보 (vertex/texture/normal 인덱스)
s (Smooth Group): 부드러운 쉐이딩 그룹 정보

마우스를 드래그하여 모델을 회전시킬 수 있다.
마우스 휠을 사용하여 모델을 확대/축소할 수 있다.
키보드의 방향키를 사용하여 모델을 이동시킬 수 있다.

기본 rendering은 위의 정보를 이용하여 하지만 light의 추가와 texture적용을 지원한다.

기본 light를 제공하여 모델의 입체감을 향상시킨다.

