# Figma 파일럿 리뷰 번들

D0~D3, P1~P5 각 디렉터리는 Figma 대조 리뷰의 기록(README·tests.md·exceptions.md·metrics.json)입니다.

**PNG는 2026-09-10에 트리에서 제거했습니다** (941장, 약 854MB — before/after/side-by-side/
overlay/difference-heatmap/figma export). 이유:

- 테스트가 판정에 쓰던 PNG는 P4의 `states/<state>-<variant>/after.png` 24장뿐이었고, 그마저
  `RoutinePlayerFigmaVisualTests`의 inline dHash 딕셔너리로 옮겼습니다(다른 스위트와 같은 방식).
- Liquid Glass 전환으로 모든 기준선이 바뀌어 PNG를 유지하면 리포가 매번 수십 MB씩 커집니다.

필요하면 히스토리에서 봅니다. 제거 직전 커밋은 `git log --diff-filter=D -- Moru/docs/figma-pilot-review-bundle`로 찾고,
`git show <그 커밋>^:Moru/docs/figma-pilot-review-bundle/P4-routine-player-completion/states/regular-confirm-light-M/after.png > /tmp/after.png`
처럼 꺼냅니다. 현재 캡처는 `bash Scripts/run-tests.sh full -only-testing:MoruTests/<스위트>`가
`build/captures/full/`에 새로 만듭니다.
